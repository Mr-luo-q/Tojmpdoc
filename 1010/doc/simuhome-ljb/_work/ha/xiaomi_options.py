r"""驱动 Xiaomi Home 集成的 options flow（用来刷新设备列表，把新设备导进来）。

为什么需要：官方集成把设备清单缓存在本地（.storage\xiaomi_home\miot_devices\），
单纯重载配置条目不会回云端刷新，必须走一次 options flow。

用法：
  python _work\ha\xiaomi_options.py                    # 只起流程，打印每一步的 schema
  python _work\ha\xiaomi_options.py '<json1>' '<json2>'  # 依次提交这些步骤
  python _work\ha\xiaomi_options.py @step1.json          # 参数以 @ 开头表示从文件读 JSON

每一步提交什么，看上一步打印出来的 data_schema / menu_options 再决定。
"""

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8123"
ROOT = Path(__file__).resolve().parents[2]
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
ENTRY_ID = "01M4K3HCFT2CZX0F31KDWVA1YQ"


def call(path: str, payload: dict) -> dict:
    """POST 一段 JSON，返回解析后的响应。"""

    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {TOKEN}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{path} -> HTTP {error.code}: {error.read().decode('utf-8')}") from None
    return json.loads(body) if body else {}


def describe(flow: dict) -> None:
    """打印一步的关键信息。"""

    print(f"  type      = {flow.get('type')}")
    print(f"  step_id   = {flow.get('step_id')}")
    print(f"  flow_id   = {flow.get('flow_id')}")
    if flow.get("title"):
        print(f"  title     = {flow.get('title')}")
    if flow.get("menu_options"):
        print(f"  menu      = {flow.get('menu_options')}")
    if flow.get("data_schema") is not None:
        print(f"  schema    = {json.dumps(flow.get('data_schema'), ensure_ascii=False)[:1400]}")
    if flow.get("errors"):
        print(f"  errors    = {flow.get('errors')}")


def main() -> int:
    # schema 里有非 GBK 字符，Windows 控制台默认编码会炸，强制 UTF-8
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    flow = call(
        "/api/config/config_entries/options/flow",
        {"handler": ENTRY_ID, "show_advanced_options": True},
    )
    print("== 第 1 步 ==")
    describe(flow)

    for index, raw in enumerate(sys.argv[1:], start=1):
        if raw.startswith("@"):
            payload = json.loads((Path(raw[1:])).read_text(encoding="utf-8"))
        else:
            payload = json.loads(raw)
        print(f"\n== 提交第 {index} 步：{json.dumps(payload, ensure_ascii=False)} ==")
        flow = call(f"/api/config/config_entries/options/flow/{flow['flow_id']}", payload)
        describe(flow)
        if flow.get("type") == "create_entry":
            print("\n流程已完成。")
            return 0

    print(f"\n停在这里。要继续就带上下一步的 JSON 再跑一次（flow_id={flow.get('flow_id')}）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
