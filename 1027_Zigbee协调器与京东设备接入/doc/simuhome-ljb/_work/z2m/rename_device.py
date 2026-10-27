"""把 Z2M 里的设备改一个干净的 friendly_name，并读回结果。"""
import json
import time

import paho.mqtt.client as mqtt

REQ = "zigbee2mqtt/bridge/request/device/rename"
RESP = "zigbee2mqtt/bridge/response/device/rename"
seen = {}


def on_message(client, userdata, msg):
    """记录响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-rename")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([(RESP, 0)])
client.loop_start()
time.sleep(1.0)

client.publish(REQ, json.dumps({"from": "0xa4c138f72c66960c", "to": "th01"})).wait_for_publish(timeout=5)
time.sleep(2.5)
print("rename response:", seen.get(RESP))
client.loop_stop()
client.disconnect()
