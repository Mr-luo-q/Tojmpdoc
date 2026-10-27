"""打印 Z2M 里当前设备的完整档案（型号、厂商、能力、入网状态）。"""
import json
import time

import paho.mqtt.client as mqtt

DEVICES = "zigbee2mqtt/bridge/devices"
STATE = "zigbee2mqtt/bridge/state"
got = {}


def on_message(client, userdata, msg):
    """把设备清单和状态存下来。"""
    got[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-inspect")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=30)
client.subscribe([(DEVICES, 0), (STATE, 0), ("zigbee2mqtt/bridge/info", 0)])
client.loop_start()
time.sleep(2.0)

devices = json.loads(got.get(DEVICES, "[]"))
for dev in devices:
    print(f"fmt={dev.get('friendly_name')}  ieee={dev.get('ieee_address')}  type={dev.get('type')}")
    print(f"  model={dev.get('model_id')}  manufacturer={dev.get('manufacturer')}")
    print(f"  interview={dev.get('interview_completed')}  supported={dev.get('supported')}")
    definition = dev.get("definition") or {}
    print(f"  definition={definition.get('model')} / {definition.get('vendor')} / {definition.get('description')}")
    exposes = definition.get("exposes") or []
    names = [e.get("property") or e.get("name") for e in exposes if isinstance(e, dict)]
    print(f"  exposes={names}")

info = json.loads(got.get("zigbee2mqtt/bridge/info", "{}"))
print("bridge state:", got.get(STATE))
print("permit_join:", info.get("permit_join"), " channel:", (info.get("network") or {}).get("channel"))

client.loop_stop()
client.disconnect()
