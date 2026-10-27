"""订阅 zigbee2mqtt/# 并只保留含 wsz01/开关 IEEE 的报文。"""
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000126f39e"
hits = []


def on_message(client, userdata, msg):
    """只记录与这颗开关相关的主题。"""
    if msg.topic.startswith("zigbee2mqtt/") and ("wsz01" in msg.topic or IEEE in msg.topic):
        payload = msg.payload.decode("utf-8", "replace")
        hits.append((msg.topic, payload))
        print(f"[{msg.topic}] {payload[:200]}", flush=True)


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-switch-watch3")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([("zigbee2mqtt/#", 0)])
client.loop_start()
print("监听 30 秒，请用力按开关……", flush=True)
time.sleep(30)
client.loop_stop()
client.disconnect()
print(f"相关报文数: {len(hits)}", flush=True)
