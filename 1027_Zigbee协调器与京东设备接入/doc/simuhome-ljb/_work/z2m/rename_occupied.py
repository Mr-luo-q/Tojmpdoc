"""把模板实体改成英文 id：binary_sensor.prz01_occupied。"""
import asyncio
import json
from pathlib import Path

import websockets

ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS = "ws://127.0.0.1:8123/api/websocket"


async def call(sock, rid, msg):
    """发 WS 命令并取 result。"""
    await sock.send(json.dumps({"id": rid, **msg}))
    while True:
        data = json.loads(await sock.recv())
        if data.get("id") == rid and data.get("type") == "result":
            if not data.get("success"):
                return None, data.get("error")
            return data.get("result"), None


async def main():
    """执行改名。"""
    async with websockets.connect(WS, max_size=16 * 1024 * 1024) as sock:
        await sock.recv()
        await sock.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        await sock.recv()
        res, err = await call(sock, 1, {
            "type": "config/entity_registry/update",
            "entity_id": "binary_sensor.prz01_you_ren",
            "new_entity_id": "binary_sensor.prz01_occupied",
        })
        print("rename:", err or res.get("entity_entry", {}).get("entity_id"))


asyncio.run(main())
