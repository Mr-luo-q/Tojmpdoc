"""打开 Z2M 的入网窗口，并读回它的响应。"""
import json
import time

import paho.mqtt.client as mqtt

HOST = "127.0.0.1"
PORT = 1883
REQ = "zigbee2mqtt/bridge/request/permit_join"
RESP = "zigbee2mqtt/bridge/response/permit_join"
STATE = "zigbee2mqtt/bridge/state"

seen = {}


def on_message(client, userdata, msg):
    """把感兴趣的主题都记下来。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-permit")
client.on_message = on_message
client.connect(HOST, PORT, keepalive=30)
client.subscribe([(RESP, 0), (STATE, 0), ("zigbee2mqtt/bridge/info", 0)])
client.loop_start()
time.sleep(1.0)

ret = client.publish(REQ, json.dumps({"value": True, "time": 254}))
ret.wait_for_publish(timeout=5)
time.sleep(2.0)

for topic in (STATE, RESP, "zigbee2mqtt/bridge/info"):
    payload = seen.get(topic)
    if topic.endswith("/info") and payload:
        payload = payload[:300]
    print(f"{topic} -> {payload}")

client.loop_stop()
client.disconnect()
