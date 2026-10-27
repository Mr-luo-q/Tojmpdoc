"""读 Z2M 的 bridge/health，看这台 PIR 累计收到多少条报文。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
got = {}


def on_message(client, userdata, msg):
    """保存 health 载荷。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-health")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([("zigbee2mqtt/bridge/health", 0)])
client.loop_start()
time.sleep(3)

health = json.loads(got.get("zigbee2mqtt/bridge/health", "{}"))
devices = health.get("devices") or {}
print("PIR 报文统计:", json.dumps(devices.get(IEEE, "无记录"), ensure_ascii=False))
print("全部设备:", json.dumps({k: v.get("messages") for k, v in devices.items()}, ensure_ascii=False))

client.loop_stop()
client.disconnect()
