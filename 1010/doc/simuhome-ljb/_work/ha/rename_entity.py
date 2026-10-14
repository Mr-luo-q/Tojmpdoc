r"""改 HA 里的 entity_id / 友好名（走 WebSocket 的 config/entity_registry/update）。

为什么需要：HA 的 MQTT discovery 不支持 object_id 键，中文设备名会被拼音化，
生出来的 id 又长又重复（实测：switch.lan_ya_yin_xiang_lan_ya_yin_xiang）。

用法：
  python _work\ha\rename_entity.py <旧 entity_id> <新 entity_id> [友好名]
"""

import asyncio
import json
import sys
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[2]
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS_URL = "ws://127.0.0.1:8123/api/websocket"


async def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    old_id, new_id = sys.argv[1], sys.argv[2]
    friendly = sys.argv[3] if len(sys.argv) > 3 else None

    payload = {"entity_id": old_id, "new_entity_id": new_id}
    if friendly:
        payload["name"] = friendly

    async with websockets.connect(WS_URL, max_size=8 * 1024 * 1024) as socket:
        await socket.recv()
        await socket.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        if json.loads(await socket.recv()).get("type") != "auth_ok":
            print("认证失败", file=sys.stderr)
            return 1

        await socket.send(json.dumps({"id": 1, "type": "config/entity_registry/update", **payload}))
        while True:
            message = json.loads(await socket.recv())
            if message.get("id") == 1 and message.get("type") == "result":
                if message.get("success"):
                    result = message.get("result") or {}
                    print(f"已改：{old_id} → {result.get('entity_id', new_id)}"
                          + (f"（友好名 {friendly}）" if friendly else ""))
                    return 0
                print(f"失败：{json.dumps(message.get('error'), ensure_ascii=False)}", file=sys.stderr)
                return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
