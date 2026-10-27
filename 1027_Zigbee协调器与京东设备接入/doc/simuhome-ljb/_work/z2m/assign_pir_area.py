"""把 prz01 挂进卧室区域，并顺便读一次它的实时状态。"""
import asyncio
import json
from pathlib import Path

import websockets

ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS = "ws://127.0.0.1:8123/api/websocket"
IEEE_SUFFIX = "0x00158d000128396d"
AREA_NAME = "卧室"


async def call(sock, rid, msg):
    """发 WS 命令并取 result。"""
    await sock.send(json.dumps({"id": rid, **msg}))
    while True:
        data = json.loads(await sock.recv())
        if data.get("id") == rid and data.get("type") == "result":
            if not data.get("success"):
                raise RuntimeError(data.get("error"))
            return data.get("result")


async def main():
    """找设备、找房间、挂进去。"""
    async with websockets.connect(WS, max_size=16 * 1024 * 1024) as sock:
        await sock.recv()
        await sock.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        await sock.recv()

        devices = await call(sock, 1, {"type": "config/device_registry/list"})
        target = None
        for dev in devices:
            ids = json.dumps(dev.get("identifiers") or [])
            if IEEE_SUFFIX in ids:
                target = dev
                break
        if target is None:
            print("没找到 prz01 的设备记录")
            return

        areas = await call(sock, 2, {"type": "config/area_registry/list"})
        area_id = next((a["area_id"] for a in areas if a.get("name") == AREA_NAME), None)
        print("device:", target.get("name"), "id:", target.get("id"), "area:", target.get("area_id"), "->", area_id)

        await call(sock, 3, {"type": "config/device_registry/update", "device_id": target["id"], "area_id": area_id})
        print("assigned")


asyncio.run(main())
