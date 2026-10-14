r"""验证 broker 的订阅过滤：只订阅一个精确主题，看会不会收到别的。

用法：python _work\broker\probe_filter.py [topic]
默认订阅 bt_speaker/v1/set，跑 8 秒，打印收到消息的「主题 → 前 60 字」。
"""

import sys
import time

import paho.mqtt.client as mqtt

TOPIC = sys.argv[1] if len(sys.argv) > 1 else "bt_speaker/v1/set"
received: list[tuple[str, str]] = []


def on_connect(client, userdata, flags, reason_code, properties=None) -> None:
    client.subscribe(TOPIC, qos=0)
    print(f"已订阅（精确主题）：{TOPIC}")


def on_message(client, userdata, message) -> None:
    flag = "retained" if message.retain else "live"
    received.append(
        (f"[{flag}] {message.topic}", message.payload.decode("utf-8", "replace")[:60])
    )


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="probe-filter")
client.on_connect = on_connect
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.loop_start()
time.sleep(8)
client.loop_stop()
client.disconnect()

print(f"共收到 {len(received)} 条")
for topic, preview in received[:20]:
    print(f"  {topic}  ::  {preview}")
