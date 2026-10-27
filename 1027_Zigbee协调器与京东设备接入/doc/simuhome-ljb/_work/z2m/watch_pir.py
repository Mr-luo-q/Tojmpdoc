"""监听这台 PIR 的 MQTT 主题，确认它触发时到底有没有上行报文。"""
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
TOPICS = [f"zigbee2mqtt/{IEEE}", f"zigbee2mqtt/{IEEE}/availability",
          f"homeassistant/binary_sensor/{IEEE}_occupancy/config"]
count = {"n": 0}


def on_message(client, userdata, msg):
    """打一条收到的报文。"""
    count["n"] += 1
    print(f"[{msg.topic}] {msg.payload.decode('utf-8', 'replace')[:300]}", flush=True)


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-pir-watch")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(t, 0) for t in TOPICS])
client.loop_start()
print("监听 45 秒，请持续挥手……", flush=True)
time.sleep(45)
client.loop_stop()
client.disconnect()
print(f"收到 {count['n']} 条报文", flush=True)
