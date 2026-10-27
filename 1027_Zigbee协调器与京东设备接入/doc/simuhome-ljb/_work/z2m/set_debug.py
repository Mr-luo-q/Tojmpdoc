"""把 Z2M 日志级别调到 debug，便于观察是否收到该设备的帧。"""
import json
import time

import paho.mqtt.client as mqtt

seen = {}


def on_message(client, userdata, msg):
    """记录响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-setdebug")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([("zigbee2mqtt/bridge/response/options", 0)])
client.loop_start()
time.sleep(1.0)
client.publish("zigbee2mqtt/bridge/request/options", json.dumps({"options": {"advanced": {"log_level": "debug"}}})).wait_for_publish(timeout=5)
time.sleep(3)
print("options:", seen.get("zigbee2mqtt/bridge/response/options", "(无)"))
client.loop_stop()
client.disconnect()
