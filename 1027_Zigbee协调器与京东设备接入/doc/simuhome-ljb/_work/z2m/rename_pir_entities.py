"""把 PIR 的 HA 实体 id 改成 prz01 前缀（Z2M 侧已改名，这里只动 HA 注册表）。"""
import asyncio
import json
from pathlib import Path

import websockets

ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS = "ws://127.0.0.1:8123/api/websocket"

RENAMES = [
    ("binary_sensor.0x00158d000128396d_alarm_1", "binary_sensor.prz01_alarm_1"),
    ("binary_sensor.0x00158d000128396d_alarm_2", "binary_sensor.prz01_alarm_2"),
    ("binary_sensor.0x00158d000128396d_tamper", "binary_sensor.prz01_tamper"),
    ("binary_sensor.0x00158d000128396d_battery_low", "binary_sensor.prz01_battery_low"),
    ("sensor.0x00158d000128396d_battery", "sensor.prz01_battery"),
    ("button.0x00158d000128396d_identify", "button.prz01_identify"),
]


async def call(sock, rid, msg):
    """发 WS 命令并取 result；失败返回错误文本。"""
    await sock.send(json.dumps({"id": rid, **msg}))
    while True:
        data = json.loads(await sock.recv())
        if data.get("id") == rid and data.get("type") == "result":
            if not data.get("success"):
                return None, data.get("error")
            return data.get("result"), None


async def main():
    """逐个改实体 id，已改过的跳过。"""
    async with websockets.connect(WS, max_size=16 * 1024 * 1024) as sock:
        await sock.recv()
        await sock.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        await sock.recv()
        rid = 1
        for old, new in RENAMES:
            res, err = await call(sock, rid, {"type": "config/entity_registry/update", "entity_id": old, "new_entity_id": new})
            if err:
                print(f"{old} -> {err.get('message', err)}")
            else:
                print(f"{old} -> {res.get('entity_entry', {}).get('entity_id')}")
            rid += 1


asyncio.run(main())
