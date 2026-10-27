"""把开关改名成 wsz01，并等 HA 那边按新名字建实体。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000126f39e"
REQ = "zigbee2mqtt/bridge/request/device/rename"
RESP = "zigbee2mqtt/bridge/response/device/rename"
seen = {}


def on_message(client, userdata, msg):
    """记录响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-rename-switch")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([(RESP, 0)])
client.loop_start()
time.sleep(1.0)
client.publish(REQ, json.dumps({"from": IEEE, "to": "wsz01"})).wait_for_publish(timeout=5)
time.sleep(4)
print("rename:", seen.get(RESP))
client.loop_stop()
client.disconnect()
