"""先看开关自称实现了哪些簇，决定绑哪个。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000126f39e"
got = {}


def on_message(client, userdata, msg):
    """保存设备清单。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-sw-clusters")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([("zigbee2mqtt/bridge/devices", 0)])
client.loop_start()
time.sleep(3)

for dev in json.loads(got.get("zigbee2mqtt/bridge/devices", "[]")):
    if dev.get("ieee_address") != IEEE:
        continue
    print("model:", dev.get("model_id"), "type:", dev.get("type"))
    for ep_id, ep in (dev.get("endpoints") or {}).items():
        c = ep.get("clusters") or {}
        print(f"  endpoint {ep_id}: input={c.get('input')}")
        print(f"                output={c.get('output')}")
        print(f"                bindings={ep.get('bindings')}")

client.loop_stop()
client.disconnect()
