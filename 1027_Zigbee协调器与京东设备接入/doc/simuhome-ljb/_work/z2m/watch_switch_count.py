"""盯 40 秒，看开关的报文计数有没有因为按键而增加。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000126f39e"
latest = {}


def on_message(client, userdata, msg):
    """保存最新的 health。"""
    latest["payload"] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-health-watch")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([("zigbee2mqtt/bridge/health", 0)])
client.loop_start()
time.sleep(2)

def count():
    """取当前开关的报文累计数。"""
    health = json.loads(latest.get("payload", "{}"))
    return (health.get("devices") or {}).get(IEEE, {}).get("messages")

start = count()
print(f"起始计数 {start}，请连续按开关 3 次……", flush=True)
for _ in range(8):
    time.sleep(5)
    print(f"  当前 {count()}", flush=True)
end = count()
print(f"结果：{start} -> {end}，{'检测到按键报文' if (end or 0) > (start or 0) else '没有任何新报文'}", flush=True)

client.loop_stop()
client.disconnect()
