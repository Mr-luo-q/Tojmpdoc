"""把 spz01 挂到卧室区域。"""
import asyncio
import json
from pathlib import Path

import websockets

ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS = "ws://127.0.0.1:8123/api/websocket"
IEEE = "0x00158d000129e0c4"


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
        target = next((d for d in devices if IEEE in json.dumps(d.get("identifiers") or [])), None)
        if not target:
            print("没找到插座设备记录")
            return
        areas = await call(sock, 2, {"type": "config/area_registry/list"})
        area_id = next((a["area_id"] for a in areas if a.get("name") == "卧室"), None)
        print("device:", target.get("name"), "area:", target.get("area_id"), "->", area_id)
        await call(sock, 3, {"type": "config/device_registry/update", "device_id": target["id"], "area_id": area_id})
        print("assigned")


asyncio.run(main())
