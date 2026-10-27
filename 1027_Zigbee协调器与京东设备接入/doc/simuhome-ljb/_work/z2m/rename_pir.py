"""把 PIR 改名成 prz01：先改 Z2M 的 friendly_name，再改 HA 的实体 id。"""
import asyncio
import json
import time
from pathlib import Path

import paho.mqtt.client as mqtt
import websockets

IEEE = "0x00158d000128396d"
ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS = "ws://127.0.0.1:8123/api/websocket"
seen = {}


def on_message(client, userdata, msg):
    """记录 Z2M 响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-rename-pir")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([("zigbee2mqtt/bridge/response/device/rename", 0)])
client.loop_start()
time.sleep(1.0)
client.publish("zigbee2mqtt/bridge/request/device/rename", json.dumps({"from": IEEE, "to": "prz01"})).wait_for_publish(timeout=5)
time.sleep(3)
print("rename:", seen.get("zigbee2mqtt/bridge/response/device/rename"))
client.loop_stop()
client.disconnect()

RENAMES = [
    ("binary_sensor.0x00158d000128396d_alarm_1", "binary_sensor.prz01_alarm_1"),
    ("binary_sensor.0x00158d000128396d_alarm_2", "binary_sensor.prz01_alarm_2"),
    ("binary_sensor.0x00158d000128396d_tamper", "binary_sensor.prz01_tamper"),
    ("binary_sensor.0x00158d000128396d_battery_low", "binary_sensor.prz01_battery_low"),
    ("sensor.0x00158d000128396d_battery", "sensor.prz01_battery"),
    ("button.0x00158d000128396d_identify", "button.prz01_identify"),
]


async def call(sock, rid, msg):
    """发 WS 命令并取 result。"""
    await sock.send(json.dumps({"id": rid, **msg}))
    while True:
        data = json.loads(await sock.recv())
        if data.get("id") == rid and data.get("type") == "result":
            if not data.get("success"):
                raise RuntimeError(data.get("error"))
            return data.get("result")


async def main():
    """执行实体改名。"""
    async with websockets.connect(WS, max_size=16 * 1024 * 1024) as sock:
        await sock.recv()
        await sock.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        await sock.recv()
        rid = 1
        for old, new in RENAMES:
            try:
                res = await call(sock, rid, {"type": "config/entity_registry/update", "entity_id": old, "new_entity_id": new})
                print(f"{old} -> {res.get('entity_entry', {}).get('entity_id')}")
            except Exception as exc:
                print(f"{old} -> FAILED {exc}")
            rid += 1


asyncio.run(main())
