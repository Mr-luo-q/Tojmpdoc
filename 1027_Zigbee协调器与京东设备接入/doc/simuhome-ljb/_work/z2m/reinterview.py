"""请求 Z2M 对指定设备重新做一次 interview，并等结果。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
REQ = "zigbee2mqtt/bridge/request/device/interview"
RESP = "zigbee2mqtt/bridge/response/device/interview"
EVENT = "zigbee2mqtt/bridge/event"
seen = {}


def on_message(client, userdata, msg):
    """记录响应与事件。"""
    if msg.topic == EVENT:
        text = msg.payload.decode("utf-8", "replace")
        if IEEE in text:
            print("[event]", text[:200], flush=True)
    else:
        seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-interview")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(RESP, 0), (EVENT, 0)])
client.loop_start()
time.sleep(1.0)

client.publish(REQ, json.dumps({"id": IEEE})).wait_for_publish(timeout=5)
time.sleep(30)
print("interview response:", seen.get(RESP, "(无)")[:400])
client.loop_stop()
client.disconnect()
