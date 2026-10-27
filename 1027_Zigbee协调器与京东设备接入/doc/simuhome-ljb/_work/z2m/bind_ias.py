"""按 Z2M 的 bind 请求格式，给 PIR 绑定协调器的 ssIasZone 簇。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
REQ = "zigbee2mqtt/bridge/request/device/bind"
RESP = "zigbee2mqtt/bridge/response/device/bind"
DEVICES = "zigbee2mqtt/bridge/devices"
got = {}


def on_message(client, userdata, msg):
    """记录响应与设备清单。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-bind2")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(RESP, 0), (DEVICES, 0)])
client.loop_start()
time.sleep(1.0)

# 关键：to 必须是字符串（设备名或 Coordinator），不能是对象
payload = {
    "from": IEEE,
    "from_endpoint": 1,
    "to": "Coordinator",
    "to_endpoint": 1,
    "clusters": ["ssIasZone"],
}
client.publish(REQ, json.dumps(payload)).wait_for_publish(timeout=5)
time.sleep(15)
print("bind response:", got.get(RESP, "(无)")[:400])

devices = json.loads(got.get(DEVICES, "[]"))
for dev in devices:
    if dev.get("ieee_address") == IEEE:
        ep = (dev.get("endpoints") or {}).get("1") or {}
        print("bindings now:", ep.get("bindings"))

client.loop_stop()
client.disconnect()
