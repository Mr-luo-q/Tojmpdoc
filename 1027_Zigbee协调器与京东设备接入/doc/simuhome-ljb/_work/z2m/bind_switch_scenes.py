"""给开关绑定协调器的 genScenes 簇（场景开关的常规做法）。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000126f39e"
REQ = "zigbee2mqtt/bridge/request/device/bind"
RESP = "zigbee2mqtt/bridge/response/device/bind"
DEVICES = "zigbee2mqtt/bridge/devices"
got = {}


def on_message(client, userdata, msg):
    """记录响应与设备清单。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-bind-scenes")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=90)
client.subscribe([(RESP, 0), (DEVICES, 0)])
client.loop_start()
time.sleep(1.0)

payload = {
    "from": "wsz01",
    "from_endpoint": 1,
    "to": "Coordinator",
    "to_endpoint": 1,
    "clusters": ["genScenes"],
}

for attempt in range(1, 11):
    got.pop(RESP, None)
    client.publish(REQ, json.dumps(payload)).wait_for_publish(timeout=5)
    time.sleep(5)
    resp = got.get(RESP)
    print(f"[{attempt}] {resp[:150] if resp else '无响应'}", flush=True)
    if resp and '"status":"ok"' in resp.replace(" ", ""):
        break

for dev in json.loads(got.get(DEVICES, "[]")):
    if dev.get("ieee_address") == IEEE:
        ep = (dev.get("endpoints") or {}).get("1") or {}
        print("bindings now:", ep.get("bindings"), flush=True)

client.loop_stop()
client.disconnect()
