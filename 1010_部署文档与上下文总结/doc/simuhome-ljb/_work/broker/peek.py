r"""看一眼 broker 上有哪些话题（验证发布器是否真的发了 discovery）。

只读探针：连上 broker 订阅 `homeassistant/#` 与 `simuhome/v1/#`，等几秒打印结果。
"""

import time

import paho.mqtt.client as mqtt

HOST = "127.0.0.1"
PORT = 1883

found: list[tuple[str, int]] = []


def on_connect(client, userdata, flags, reason_code, properties=None) -> None:
    client.subscribe("homeassistant/#", qos=0)
    client.subscribe("simuhome/v1/#", qos=0)


def on_message(client, userdata, msg) -> None:
    found.append((msg.topic, len(msg.payload)))


def main() -> None:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="peek")
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(HOST, PORT, keepalive=30)
    client.loop_start()
    time.sleep(5)
    client.loop_stop()
    client.disconnect()

    discovery = [t for t, _ in found if t.startswith("homeassistant/")]
    others = [t for t, _ in found if not t.startswith("homeassistant/")]
    print(f"总话题数 {len(found)}")
    print(f"discovery 话题 {len(discovery)} 条，状态话题 {len(others)} 条")
    for topic in discovery[:20]:
        print("  discovery:", topic)
    for topic in others[:5]:
        print("  state:", topic)


if __name__ == "__main__":
    main()
