"""盯 60 秒，看 prz01_occupied 有没有因为有人而变成 on。"""
import time
from pathlib import Path

import requests

ROOT = Path(r"D:\项目\simuhome-ljb")
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()
URL = "http://127.0.0.1:8123/api/states/binary_sensor.prz01_occupied"
HEAD = {"Authorization": f"Bearer {TOKEN}"}

last = None
seen_on = False
end = time.time() + 60
while time.time() < end:
    try:
        resp = requests.get(URL, headers=HEAD, timeout=5).json()
        state = resp.get("state")
        stamp = resp.get("last_updated", "")[11:19]
        if state != last:
            print(f"{stamp}  occupied = {state}", flush=True)
            last = state
        if state == "on":
            seen_on = True
    except Exception as exc:
        print("轮询失败:", type(exc).__name__, exc, flush=True)
    time.sleep(1.5)

print("结果:", "期间检测到有人（on）" if seen_on else "期间一直是 off，没有检测到人", flush=True)
