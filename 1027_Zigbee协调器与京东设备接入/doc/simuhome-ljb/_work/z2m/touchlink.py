"""试 Touchlink：先扫描附近支持 Touchlink 的设备，再对目标做强制复位。"""
import json
import time

import paho.mqtt.client as mqtt

SCAN_REQ = "zigbee2mqtt/bridge/request/touchlink/scan"
SCAN_RESP = "zigbee2mqtt/bridge/response/touchlink/scan"
RESET_REQ = "zigbee2mqtt/bridge/request/touchlink/factory_reset"
RESET_RESP = "zigbee2mqtt/bridge/response/touchlink/factory_reset"
seen = {}


def on_message(client, userdata, msg):
    """记录响应。"""
    seen[msg.topic] = msg.payload.decode("utf-8", "replace")


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="z2m-touchlink")
client.on_message = on_message
client.connect("127.0.0.1", 1883, keepalive=60)
client.subscribe([(SCAN_RESP, 0), (RESET_RESP, 0)])
client.loop_start()
time.sleep(1.0)

client.publish(SCAN_REQ, json.dumps({"transaction": int(time.time()) % 10000})).wait_for_publish(timeout=5)
time.sleep(25)
print("scan:", seen.get(SCAN_RESP, "(无响应)")[:600])

if "ok" in str(seen.get(SCAN_RESP, "")):
    client.publish(RESET_REQ, json.dumps({"transaction": int(time.time()) % 10000})).wait_for_publish(timeout=5)
    time.sleep(20)
    print("reset:", seen.get(RESET_RESP, "(无响应)")[:600])

client.loop_stop()
client.disconnect()
