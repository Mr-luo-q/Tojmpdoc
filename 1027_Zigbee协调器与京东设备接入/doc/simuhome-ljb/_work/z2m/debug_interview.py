"""把 Z2M 日志切到 debug，再发起一次 interview，便于定位卡在哪一步。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
OPT_REQ = "zigbee2mqtt/bridge/request/options"
OPT_RESP = "zigbee2mqtt/bridge/response/options"
INT_REQ = "zigbee2mqtt/bridge/request/device/interview"
INT_RESP = "zigbee2mqtt/bridge/response/device/interview"
seen = {}


def on_message(client, userdata, msg):
    """记录响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-debug")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(OPT_RESP, 0), (INT_RESP, 0)])
client.loop_start()
time.sleep(1.0)

client.publish(OPT_REQ, json.dumps({"options": {"advanced": {"log_level": "debug"}}})).wait_for_publish(timeout=5)
time.sleep(3)
print("options:", seen.get(OPT_RESP, "(无)")[:200], flush=True)

client.publish(INT_REQ, json.dumps({"id": IEEE})).wait_for_publish(timeout=5)
time.sleep(30)
print("interview:", seen.get(INT_RESP, "(无)")[:300], flush=True)

client.loop_stop()
client.disconnect()
