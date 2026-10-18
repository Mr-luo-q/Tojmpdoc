"""HA WebSocket 小工具：用长期令牌执行一条 WS 命令并打印结果。"""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path

import websockets


TOKEN_PATH = Path(__file__).resolve().parent.parent / "_secrets" / "ha_token.txt"


async def run(command: str, params: dict) -> dict:
    """连上 HA 的 WebSocket，认证后发一条命令，返回结果。"""

    token = TOKEN_PATH.read_text(encoding="utf-8").strip()
    async with websockets.connect("ws://localhost:8123/api/websocket", max_size=8 * 1024 * 1024) as ws:
        await ws.recv()  # auth_required
        await ws.send(json.dumps({"type": "auth", "access_token": token}))
        auth = json.loads(await ws.recv())
        if auth.get("type") != "auth_ok":
            raise RuntimeError(f"认证失败：{auth}")
        await ws.send(json.dumps({"id": 1, "type": command, **params}))
        while True:
            message = json.loads(await ws.recv())
            if message.get("id") == 1 and message.get("type") == "result":
                return message


def main() -> None:
    """命令行入口：python ha_ws.py <command> [json-params]。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("command", help="例如 config/area_registry/list")
    parser.add_argument("params", nargs="?", default="{}", help="JSON 形式的附加参数")
    parser.add_argument("--full", action="store_true", help="打印完整结果")
    args = parser.parse_args()

    result = asyncio.run(run(args.command, json.loads(args.params)))
    data = result.get("result")
    if isinstance(data, list):
        print(f"命令 {args.command} 成功，返回 {len(data)} 条")
        payload = json.dumps(data if args.full else data[:3], ensure_ascii=False, indent=2)
        print(payload[:2000])
    else:
        print(f"命令 {args.command} 成功：{json.dumps(data, ensure_ascii=False)[:500]}")


if __name__ == "__main__":
    main()
