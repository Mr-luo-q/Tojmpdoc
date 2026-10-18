#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""安全关机：通过 SSH 执行 sudo poweroff，然后验证确实已关机。"""
import time
import paramiko

HOST = "192.168.137.2"

cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
cli.connect(HOST, username="pi", password="<口令已脱敏>",
            look_for_keys=False, allow_agent=False, timeout=10)

# 关机前先记一下状态，确认它是在正常状态被关的
_, o, _ = cli.exec_command("uptime; sync; echo '--- 即将关机 ---'", timeout=15)
print(o.read().decode("utf-8", "replace").strip())

# 先 sync 再 poweroff，尽量把缓存落到卡上
_, o, e = cli.exec_command("sudo -S poweroff", timeout=20)
o.channel.send("password\n")
try:
    print("poweroff 输出:", o.read().decode("utf-8", "replace").strip())
except Exception as ex:
    print("(连接按预期断开):", type(ex).__name__)

try:
    cli.close()
except Exception:
    pass

print("\n等待关机…")
time.sleep(12)

# 验证：ping + 22 端口都应该没了
import socket
import subprocess

for attempt in range(1, 7):
    r = subprocess.run(["ping", "-n", "1", "-w", "1000", HOST],
                       capture_output=True, text=True)
    alive = ("TTL=" in r.stdout)
    s = socket.socket(); s.settimeout(3)
    port22 = False
    try:
        s.connect((HOST, 22)); port22 = True
    except Exception:
        pass
    finally:
        s.close()

    print(f"  第 {attempt} 次检查: ping={'通' if alive else '不通'}  22端口={'开' if port22 else '关'}")
    if not alive and not port22:
        print("\n>>> 树莓派已关机，可以安全拔电源。")
        break
    time.sleep(8)
else:
    print("\n>>> 仍未完全关机，再等一会儿或检查绿色 ACT 灯是否停止闪烁。")
