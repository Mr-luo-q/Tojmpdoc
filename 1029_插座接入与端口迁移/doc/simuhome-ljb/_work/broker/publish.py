r"""往本机 broker 发一条消息（排查和测试用）。

用法：
  python _work\broker\publish.py <topic> <payload> [--retain]
  python _work\broker\publish.py bt_speaker/v1/set ""        # 清掉该主题的 retained
"""

import os
import sys
import time

import paho.mqtt.client as mqtt

# 端口与 broker 保持一致，可用 MQTT_PORT 覆盖（见 run_broker.py 的说明）
PORT = int(os.environ.get("MQTT_PORT", "1883"))

if len(sys.argv) < 2:
    raise SystemExit(__doc__)

topic = sys.argv[1]
payload = sys.argv[2] if len(sys.argv) > 2 else ""
retain = "--retain" in sys.argv

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="probe-publish")
client.connect("127.0.0.1", PORT, keepalive=30)
client.loop_start()
time.sleep(0.5)
client.publish(topic, payload, retain=retain)
time.sleep(0.8)
client.loop_stop()
client.disconnect()
print(f"已发布 topic={topic!r} payload={payload!r} retain={retain}")
