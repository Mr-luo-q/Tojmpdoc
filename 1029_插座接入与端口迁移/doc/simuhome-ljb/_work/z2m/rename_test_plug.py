"""把插座改名为 spz01，并向它下发一次开关命令验证控制链路。"""
import json
import os
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000129e0c4"
PORT = int(os.environ.get("MQTT_PORT", "1883"))
got = {}


def on_message(client, userdata, msg):
    """记录状态与响应。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-plug-test")
client.on_message = on_message
client.connect("127.0.0.1", PORT, keepalive=60)
client.subscribe([
    ("zigbee2mqtt/bridge/response/device/rename", 0),
    ("zigbee2mqtt/bridge/devices", 0),
])
client.loop_start()
time.sleep(1.0)

client.publish("zigbee2mqtt/bridge/request/device/rename", json.dumps({"from": IEEE, "to": "spz01"})).wait_for_publish(timeout=5)
time.sleep(4)
print("rename:", got.get("zigbee2mqtt/bridge/response/device/rename", "(无)")[:150], flush=True)

# 订阅改名后的状态主题，再下发指令
client.subscribe([("zigbee2mqtt/spz01", 0), ("zigbee2mqtt/spz01/state", 0)])
time.sleep(1.0)

for command in ("ON", "OFF", "ON"):
    client.publish("zigbee2mqtt/spz01/set", json.dumps({"state": command})).wait_for_publish(timeout=5)
    time.sleep(3)
    print(f"下发 {command} -> 状态 {got.get('zigbee2mqtt/spz01') or got.get('zigbee2mqtt/spz01/state')}", flush=True)

client.loop_stop()
client.disconnect()
