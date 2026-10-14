r"""盘一下 HA 的集成与实体分布（按 platform 分组），走 WebSocket API。

用途：装完小米后确认导入了多少设备、集成条目状态是否正常。
用法：python _work\ha\inspect_entities.py
"""

import asyncio
import json
from collections import Counter
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[2]
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS_URL = "ws://127.0.0.1:8123/api/websocket"


async def call(socket, request_id: int, message: dict) -> object:
    """发一条 WS 命令并等它的 result。"""

    await socket.send(json.dumps({"id": request_id, **message}))
    while True:
        data = json.loads(await socket.recv())
        if data.get("id") == request_id and data.get("type") == "result":
            if not data.get("success"):
                raise RuntimeError(data.get("error"))
            return data.get("result")


async def main() -> None:
    async with websockets.connect(WS_URL, max_size=16 * 1024 * 1024) as socket:
        await socket.recv()
        await socket.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        if json.loads(await socket.recv()).get("type") != "auth_ok":
            raise SystemExit("认证失败")

        print("== 集成条目 ==")
        for entry in await call(socket, 1, {"type": "config_entries/get"}):
            print(f"  {entry.get('domain'):<18} {entry.get('title')}  state={entry.get('state')}")

        registry = await call(socket, 2, {"type": "config/entity_registry/list"})
        print("\n== 实体按 platform 分组 ==")
        for platform, count in Counter(item.get("platform") for item in registry).most_common():
            print(f"  {platform:<18} {count}")

        rows = sorted(
            (item for item in registry if item.get("platform") == "xiaomi_home"),
            key=lambda item: item.get("entity_id") or "",
        )
        print(f"\n== xiaomi_home 的实体（{len(rows)} 个）==")
        for item in rows:
            print(f"  {item.get('entity_id'):<52} {item.get('unique_id')}")


if __name__ == "__main__":
    asyncio.run(main())
