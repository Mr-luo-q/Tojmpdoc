r"""交互式对话：在终端里跟 DeepSeek 说话，让它经我们的 MCP 去读 / 控 HA 里的设备。

它是 E 路线的最短可用形态：模型在外部，工具由 MCP 提供，HA 只当被控后端。

用法（在哪个目录调用都行，脚本内部全是绝对路径）：
    python D:\项目\simuhome-ljb\_work\mcp\chat.py

交互命令：
    /tools     列出模型当前能用的工具
    /quit      退出（Ctrl+C 也行）
    其它输入    当作中文/英文指令发给模型

安全：默认允许写。每次工具调用都会打印出来（工具名、参数、ok、verified），
      所以你真能看见它动了哪台设备。想只看不写，把下面的 ALLOW_WRITE 改成 False。
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from openai import OpenAI

# Windows 控制台默认编码是 GBK，管道进来的中文会被解码成代理对，
# 直接炸在 API 调用上。这里把标准输入输出统一切到 UTF-8，并用 replace 兜底。
for _stream in (sys.stdin, sys.stdout):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

HERE = Path(__file__).resolve().parent                  # _work\mcp
REPO_ROOT = HERE.parents[1]                             # 仓库根
PROJECT_ROOT = REPO_ROOT / "ha_mcp_universal"           # MCP 源码包
MCP_ENTRY_SRC = PROJECT_ROOT / "src"

CONFIG_PATH = HERE / "config.yaml"
ENV_PATH = REPO_ROOT / "ha_mcp_server" / ".env"
TOKEN_PATH = REPO_ROOT / "_secrets" / "ha_token.txt"

MAX_TOOL_STEPS = 12                                     # 单轮最多允许多少次工具调用
ALLOW_WRITE = True                                      # False 时只保留读类工具
WRITE_DENY = {"fridge_cold", "fridge_freeze"}           # 名单里的设备一律不下发写命令
                                                        # （真米家冰箱，人不在旁边看不到状态）
SYSTEM_PROMPT = (
    "你是家庭环境助手，通过工具读取和控制这个家。"
    "无论用户用什么语言提问，都用中文回答。"
    "回答要短，不要复述工具返回的原始 JSON。"
)


def build_client() -> tuple[OpenAI, str, str]:
    r"""按 ha_mcp_server\.env 建 DeepSeek 客户端，返回 (客户端, 模型名, 思考模式)。"""

    if ENV_PATH.exists():
        load_dotenv(ENV_PATH)
    api_key = (os.environ.get("DEEPSEEK_API_KEY") or "").strip()
    if not api_key:
        raise SystemExit(f"DEEPSEEK_API_KEY 为空：请在 {ENV_PATH} 填入密钥")
    base_url = (os.environ.get("DEEPSEEK_BASE_URL") or "https://api.deepseek.com").strip()
    model = (os.environ.get("DEEPSEEK_MODEL") or "deepseek-flash").strip()
    thinking = (os.environ.get("DEEPSEEK_THINKING") or "disabled").strip()
    return OpenAI(api_key=api_key, base_url=base_url), model, thinking


def tools_for_model(tools: list[Any]) -> list[dict[str, Any]]:
    """把 MCP 的工具清单转成 OpenAI function calling 的格式。"""

    items = [
        {
            "type": "function",
            "function": {
                "name": tool.name,
                "description": tool.description or "",
                "parameters": tool.inputSchema,
            },
        }
        for tool in tools
    ]
    if ALLOW_WRITE:
        return items
    return [item for item in items if item["function"]["name"] != "execute_action"]


def payload_of(result: Any) -> dict[str, Any]:
    """把一次 tools/call 的返回解析成统一外壳。"""

    text = result.content[0].text if result.content else "{}"
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"ok": False, "error": {"code": "BAD_PAYLOAD", "message": text[:200]}}


def describe_call(name: str, arguments: dict[str, Any], payload: dict[str, Any]) -> str:
    """把一次工具调用压成一行给人看的摘要。"""

    data = payload.get("data") or {}
    bits = [f"{name} ok={payload.get('ok')}"]
    if arguments:
        bits.append("args=" + json.dumps(arguments, ensure_ascii=False))
    if data.get("verified") is not None:
        bits.append(f"verified={data['verified']}")
    if data.get("state_after"):
        bits.append("after=" + json.dumps(data["state_after"], ensure_ascii=False))
    error = (payload.get("error") or {}).get("code")
    if error:
        bits.append(f"error={error}")
    return "  ".join(bits)


def is_denied(device_id: Any) -> bool:
    """判断一台设备是否落在禁止写入名单里。"""

    return str(device_id) in WRITE_DENY


async def run_turn(
    client: OpenAI,
    model: str,
    thinking: str,
    session: ClientSession,
    tools: list[Any],
    history: list[dict[str, Any]],
    user_text: str,
) -> str:
    """把一句话交给模型，跟完它所有的工具调用，返回最终答复文本。

    history 会被就地追加（system 之外的 system/user/assistant/tool 消息），
    所以多轮对话能带上上下文。
    """

    history.append({"role": "user", "content": user_text})
    final_text = ""
    for _ in range(MAX_TOOL_STEPS):
        response = await asyncio.to_thread(
            lambda: client.chat.completions.create(
                model=model,
                messages=history,
                tools=tools_for_model(tools),
                tool_choice="auto",
                extra_body={"thinking": {"type": thinking}},
            )
        )
        message = response.choices[0].message
        history.append(message.model_dump(exclude_none=True))
        if not message.tool_calls:
            final_text = message.content or ""
            break
        for tool_call in message.tool_calls:
            name = tool_call.function.name
            try:
                arguments = json.loads(tool_call.function.arguments or "{}")
            except json.JSONDecodeError:
                arguments = {}
            if name == "execute_action" and is_denied(arguments.get("device_id")):
                # 本地拦下：命令根本不进 MCP，模型会收到结构化拒绝并自行改口
                payload = {
                    "ok": False,
                    "data": None,
                    "error": {
                        "code": "WRITE_DENIED",
                        "message": f"{arguments.get('device_id')} 在禁止写入名单里（本机策略），本机不下发这条命令",
                    },
                }
            else:
                payload = payload_of(await session.call_tool(name, arguments))
            print("   · " + describe_call(name, arguments, payload))
            history.append(
                {
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "content": json.dumps(payload, ensure_ascii=False),
                }
            )
    else:
        final_text = f"（工具调用超过 {MAX_TOOL_STEPS} 步，本轮提前结束）"
    return final_text


async def main_async() -> int:
    """起 MCP server，然后进 REPL。"""

    client, model, thinking = build_client()
    os.environ.setdefault("MCP_TOKEN", "local-dev-token")
    if not os.environ.get("HA_TOKEN") and TOKEN_PATH.exists():
        os.environ["HA_TOKEN"] = TOKEN_PATH.read_text(encoding="utf-8").strip()

    parameters = StdioServerParameters(
        command=sys.executable,
        args=["-m", "home_mcp.entry", "--config", str(CONFIG_PATH)],
        cwd=str(HERE),
        env={**os.environ, "PYTHONPATH": str(MCP_ENTRY_SRC)},
    )
    async with stdio_client(parameters) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            tools = (await session.list_tools()).tools
            history: list[dict[str, Any]] = [{"role": "system", "content": SYSTEM_PROMPT}]

            print(f"模型 {model}（thinking={thinking}）  工具 {len(tools)} 个")
            print(f"写入{'已开启' if ALLOW_WRITE else '已关闭'}   /tools 看工具   /quit 退出")
            if WRITE_DENY:
                print("拒写名单：" + "、".join(sorted(WRITE_DENY)) + "（命令不会下发）")
            print("直接打字下指令，例如：客厅侧灯开着吗？  把客厅侧灯打开")

            while True:
                try:
                    line = await asyncio.to_thread(input, "\n你> ")
                except (EOFError, KeyboardInterrupt):
                    print()
                    break
                # 清掉可能的代理对：非法字符替换掉，别让它传进 API
                text = line.encode("utf-8", "replace").decode("utf-8", "replace").strip()
                if not text:
                    continue
                if text in ("/quit", "/exit"):
                    break
                if text == "/tools":
                    for tool in tools:
                        print(f"   · {tool.name}: {(tool.description or '').strip()[:70]}")
                    continue
                try:
                    answer = await run_turn(client, model, thinking, session, tools, history, text)
                except Exception as error:  # noqa: BLE001
                    print(f"   · 调用失败：{type(error).__name__}: {error}")
                    continue
                print(f"\n模型> {answer.strip()}")
    return 0


def main() -> int:
    """命令行入口。"""

    return asyncio.run(main_async())


if __name__ == "__main__":
    raise SystemExit(main())
