"""看这台 PIR 自报的端点与簇，判断它到底用 IAS Zone 还是涂鸦私有簇。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
got = {}


def on_message(client, userdata, msg):
    """保存设备清单。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-clusters")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([("zigbee2mqtt/bridge/devices", 0)])
client.loop_start()
time.sleep(3)

devices = json.loads(got.get("zigbee2mqtt/bridge/devices", "[]"))
for dev in devices:
    if dev.get("ieee_address") != IEEE:
        continue
    print("type:", dev.get("type"), "model:", dev.get("model_id"), "manufacturer:", dev.get("manufacturer"))
    for ep_id, ep in (dev.get("endpoints") or {}).items():
        clusters = ep.get("clusters") or {}
        print(f"  endpoint {ep_id}")
        print("    input :", clusters.get("input"))
        print("    output:", clusters.get("output"))
        print("    bindings:", ep.get("bindings"))
    print("  interview_completed:", dev.get("interview_completed"))
    print("  supported:", dev.get("supported"))

client.loop_stop()
client.disconnect()
