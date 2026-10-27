"""监听 Z2M 的入网事件，有设备加入就打印出来。"""
import json
import time

import paho.mqtt.client as mqtt

EVENT = "zigbee2mqtt/bridge/event"
DEVICES = "zigbee2mqtt/bridge/devices"
STATE = "zigbee2mqtt/bridge/state"

deadline = time.time() + 300


def on_message(client, userdata, msg):
    """只打印入网、设备清单、掉线三类消息。"""
    text = msg.payload.decode("utf-8", "replace")
    if msg.topic == EVENT:
        print(f"[event] {text[:400]}", flush=True)
    elif msg.topic == STATE:
        print(f"[state] {text}", flush=True)
    elif msg.topic == DEVICES:
        try:
            items = json.loads(text)
            ids = [i.get("friendly_name") for i in items if i.get("type") != "Coordinator"]
            print(f"[devices] {len(ids)} 个设备: {ids}", flush=True)
        except Exception:
            print(f"[devices] {text[:200]}", flush=True)


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-watch")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([(EVENT, 0), (DEVICES, 0), (STATE, 0)])
client.loop_start()
print("监听中：等待设备入网（最长 5 分钟）", flush=True)

while time.time() < deadline:
    time.sleep(1)

client.loop_stop()
client.disconnect()
print("监听结束", flush=True)
