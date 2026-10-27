"""读这台温湿度计的最新状态，顺便看保留的 state 主题。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0xa4c138f72c66960c"
TOPIC = f"zigbee2mqtt/{IEEE}"
got = {}


def on_message(client, userdata, msg):
    """记录收到的状态。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-read")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([(TOPIC, 0), (f"{TOPIC}/availability", 0)])
client.loop_start()
time.sleep(3.0)

state = got.get(TOPIC)
print("state topic:", state or "(还没有上报)")
if state:
    print("parsed:", json.loads(state))
print("availability:", got.get(f"{TOPIC}/availability"))

client.loop_stop()
client.disconnect()
