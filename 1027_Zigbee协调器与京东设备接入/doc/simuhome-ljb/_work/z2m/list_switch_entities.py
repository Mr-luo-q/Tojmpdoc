"""列出开关设备在 HA 注册表里的全部实体（含被禁用的）。"""
import asyncio
import json
from pathlib import Path

import websockets

ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
WS = "ws://127.0.0.1:8123/api/websocket"
IEEE = "0x00158d000126f39e"


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
    """打印实体与禁用状态。"""
    async with websockets.connect(WS, max_size=16 * 1024 * 1024) as sock:
        await sock.recv()
        await sock.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        await sock.recv()
        devices = await call(sock, 1, {"type": "config/device_registry/list"})
        target = next((d for d in devices if IEEE in json.dumps(d.get("identifiers") or [])), None)
        print("device:", target.get("name") if target else None, target.get("id") if target else None)
        entries = await call(sock, 2, {"type": "config/entity_registry/list"})
        for item in entries:
            if target and item.get("device_id") == target.get("id"):
                print(f"  {item.get('entity_id'):<45} disabled_by={item.get('disabled_by')} unique_id={item.get('unique_id')}")


asyncio.run(main())
