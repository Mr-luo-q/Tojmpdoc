r"""常驻 MQTT broker（amqtt，纯 Python）。

为什么不用 Mosquitto：本机 Docker Hub（registry-1.docker.io）不通，拉不到
eclipse-mosquitto 镜像；仓库自带的 `_tools\mqtt\README.md` 给出的本机可行路线之一就是 amqtt。
这里的最小配置照搬 `_tools\mqtt\probe_mqtt.py` 里已经实测过的写法（单向监听、允许匿名、
不做主题校验），只是把端口从探针的 18830 换成正式的 1883。

启动：python D:\项目\simuhome-ljb\_work\broker\run_broker.py
端口：127.0.0.1:1883（HA 容器经 host.docker.internal 访问宿主回环，见 deploy\03 的说明）

安全：只监听环回、不做鉴权。适合本机沙盒；不要改成 0.0.0.0 后裸露到局域网/公网。
"""

import asyncio
import logging

from amqtt.broker import Broker

HOST = "127.0.0.1"
PORT = 1883

CONFIG = {
    "listeners": {
        "default": {"type": "tcp", "bind": f"{HOST}:{PORT}", "max_connections": 100}
    },
    "sys_interval": 0,
    "auth": {"allow-anonymous": True},
    "topic-check": {"enabled": False},
}


async def main() -> None:
    logging.basicConfig(level=logging.WARNING)
    broker = Broker(CONFIG)
    await broker.start()
    print(f"amqtt broker listening on {HOST}:{PORT}", flush=True)
    try:
        await asyncio.Event().wait()
    finally:
        await broker.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
