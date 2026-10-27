"""强制移除这台未完成 interview 的设备，并重开入网窗口，准备一次干净的重入网。"""
import json
import time

import paho.mqtt.client as mqtt

IEEE = "0x00158d000128396d"
RM_REQ = "zigbee2mqtt/bridge/request/device/remove"
RM_RESP = "zigbee2mqtt/bridge/response/device/remove"
PJ_REQ = "zigbee2mqtt/bridge/request/permit_join"
PJ_RESP = "zigbee2mqtt/bridge/response/permit_join"
seen = {}


def on_message(client, userdata, msg):
    """记录响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-reset")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(RM_RESP, 0), (PJ_RESP, 0)])
client.loop_start()
time.sleep(1.0)

client.publish(RM_REQ, json.dumps({"id": IEEE, "force": True})).wait_for_publish(timeout=5)
time.sleep(6)
print("remove:", seen.get(RM_RESP, "(无)")[:200], flush=True)

client.publish(PJ_REQ, json.dumps({"value": True, "time": 254})).wait_for_publish(timeout=5)
time.sleep(3)
print("permit_join:", seen.get(PJ_RESP, "(无)")[:200], flush=True)

client.loop_stop()
client.disconnect()
