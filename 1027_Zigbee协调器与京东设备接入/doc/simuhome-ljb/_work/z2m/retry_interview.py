"""在设备被唤醒的窗口里反复请求 interview，直到拿到 modelID。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
REQ = "zigbee2mqtt/bridge/request/device/interview"
DEVICES = "zigbee2mqtt/bridge/devices"
EVENT = "zigbee2mqtt/bridge/event"
got = {}


def on_message(client, userdata, msg):
    """记录设备清单与事件。"""
    if msg.topic == EVENT:
        text = msg.payload.decode("utf-8", "replace")
        if IEEE in text and "interview" in text:
            print("[interview]", text[:160], flush=True)
    else:
        got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-interview2")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(EVENT, 0), (DEVICES, 0)])
client.loop_start()
time.sleep(1.0)

for attempt in range(1, 4):
    print(f"--- 第 {attempt} 次请求 interview ---", flush=True)
    client.publish(REQ, json.dumps({"id": IEEE})).wait_for_publish(timeout=5)
    time.sleep(35)
    devices = json.loads(got.get(DEVICES, "[]"))
    target = next((d for d in devices if d.get("ieee_address") == IEEE), None)
    if target and target.get("model_id"):
        print("拿到 model:", target.get("model_id"), "manufacturer:", target.get("manufacturer"),
              "interview:", target.get("interview_completed"), flush=True)
        break

client.loop_stop()
client.disconnect()
