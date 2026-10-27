"""放宽事务超时后重试 interview：老设备睡眠久，30 秒默认值不够。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
OPT_REQ = "zigbee2mqtt/bridge/request/options"
OPT_RESP = "zigbee2mqtt/bridge/response/options"
INT_REQ = "zigbee2mqtt/bridge/request/device/interview"
INT_RESP = "zigbee2mqtt/bridge/response/device/interview"
EVENT = "zigbee2mqtt/bridge/event"
seen = {}


def on_message(client, userdata, msg):
    """记录响应与 interview 事件。"""
    if msg.topic == EVENT:
        text = msg.payload.decode("utf-8", "replace")
        if IEEE in text and "interview" in text:
            print("[interview]", text[:120], flush=True)
    else:
        seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-longtimeout")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=90)
client.subscribe([(OPT_RESP, 0), (INT_RESP, 0), (EVENT, 0)])
client.loop_start()
time.sleep(1.0)

client.publish(OPT_REQ, json.dumps({"options": {"advanced": {"transaction_timeout": 60000, "log_level": "debug"}}})).wait_for_publish(timeout=5)
time.sleep(4)
print("options:", seen.get(OPT_RESP, "(无)")[:200], flush=True)

time.sleep(5)   # 等上一次 interview 彻底结束
client.publish(INT_REQ, json.dumps({"id": IEEE})).wait_for_publish(timeout=5)
time.sleep(75)
print("interview:", seen.get(INT_RESP, "(无)")[:300], flush=True)

client.loop_stop()
client.disconnect()
