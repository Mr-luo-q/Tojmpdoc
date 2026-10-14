"""MQTT 可用性探针：本机起一个 amqtt broker，量发布到订阅的延迟与吞吐。"""

import asyncio
import json
import statistics
import threading
import time

import paho.mqtt.client as mqtt
from amqtt.broker import Broker


HOST = "127.0.0.1"
PORT = 18830
TOPIC = "probe/state"
LATENCY_COUNT = 50
BURST_COUNT = 500


def broker_config() -> dict:
    """最小 broker 配置：单向监听、允许匿名、不做主题校验。"""

    return {
        "listeners": {
            "default": {"type": "tcp", "bind": f"{HOST}:{PORT}", "max_connections": 100}
        },
        "sys_interval": 0,
        "auth": {"allow-anonymous": True},
        "topic-check": {"enabled": False},
    }


def make_client(name: str) -> mqtt.Client:
    """按 paho 2.x 的接口创建客户端。"""

    return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=name)


async def run_probe() -> None:
    """起 broker、跑延迟与吞吐两段测试、再关掉 broker。"""

    broker = Broker(broker_config())
    await broker.start()
    try:
        await asyncio.sleep(0.5)
        latencies: list[float] = []
        received = threading.Event()
        state = {"count": 0}

        def on_message(_client, _userdata, msg) -> None:
            """收到消息就记录延迟，用于统计。"""

            payload = json.loads(msg.payload.decode())
            latencies.append((time.perf_counter() - payload["t0"]) * 1000)
            state["count"] += 1
            if state["count"] >= LATENCY_COUNT + BURST_COUNT:
                received.set()

        sub = make_client("probe-sub")
        sub.on_message = on_message
        sub.connect(HOST, PORT, keepalive=30)
        sub.subscribe(TOPIC, qos=0)
        sub.loop_start()
        await asyncio.sleep(0.3)

        pub = make_client("probe-pub")
        pub.connect(HOST, PORT, keepalive=30)
        pub.loop_start()
        await asyncio.sleep(0.3)

        # 第一段：间隔 20 毫秒发 50 条，量“发布 → 收到”的延迟
        for i in range(LATENCY_COUNT):
            body = json.dumps({"i": i, "t0": time.perf_counter()})
            pub.publish(TOPIC, body, qos=0)
            await asyncio.sleep(0.02)
        await asyncio.sleep(0.5)
        latency_sample = latencies[:LATENCY_COUNT]

        # 第二段：尽可能快地连发 500 条，量吞吐
        burst_start = time.perf_counter()
        for i in range(BURST_COUNT):
            pub.publish(TOPIC, json.dumps({"i": i, "t0": time.perf_counter()}), qos=0)
        while state["count"] < LATENCY_COUNT + BURST_COUNT and time.perf_counter() - burst_start < 10:
            await asyncio.sleep(0.05)
        burst_elapsed = time.perf_counter() - burst_start

        ordered = sorted(latency_sample)
        p95 = ordered[int(len(ordered) * 0.95) - 1] if ordered else float("nan")
        print("broker 端口                : %s:%d" % (HOST, PORT))
        print("延迟测试（qos=0，间隔 20ms，n=%d）" % len(ordered))
        print("  平均 %.3f ms ｜ 中位 %.3f ms ｜ p95 %.3f ms ｜ 最大 %.3f ms" % (
            statistics.mean(ordered), statistics.median(ordered), p95, max(ordered)))
        print("吞吐测试（连发 %d 条）" % BURST_COUNT)
        print("  用时 %.3f s ｜ 约 %.0f 条/秒" % (burst_elapsed, BURST_COUNT / burst_elapsed))

        pub.loop_stop()
        sub.loop_stop()
        pub.disconnect()
        sub.disconnect()
    finally:
        await broker.shutdown()


if __name__ == "__main__":
    asyncio.run(run_probe())
