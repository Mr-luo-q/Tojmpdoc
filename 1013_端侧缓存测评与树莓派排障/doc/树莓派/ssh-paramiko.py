#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""paramiko SSH 检查（最终）。"""
import paramiko

host = "192.168.137.2"
cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    cli.connect(host, port=22, username="pi", password="<口令已脱敏>",
                look_for_keys=False, allow_agent=False, timeout=10)
    print("LOGIN_OK")

    cmds = [
        "hostname",
        "ip -br addr show eth0",
        "ip -br addr show wlan0",
        "systemctl is-active NetworkManager",
        "ls /etc/NetworkManager/system-connections/",
        "grep -H '^ssid=' /etc/NetworkManager/system-connections/* 2>/dev/null",
        "systemctl is-active ssh",
        "ss -lntp 2>/dev/null | grep ':22'",
        "cat /sys/fs/ext4/mmcblk0p2/state",
        "cat /sys/fs/ext4/mmcblk0p2/errors_count",
        "ls -l /etc/rc.local",
    ]
    for c in cmds:
        _, out, err = cli.exec_command(c, timeout=15)
        o = out.read().decode("utf-8", "replace").strip()
        e = err.read().decode("utf-8", "replace").strip()
        print(f"$ {c}")
        if o: print(o)
        if e: print("[stderr]", e)
        print()
except paramiko.AuthenticationException:
    print("AUTH_FAIL: 密码错误")
except Exception as ex:
    print(f"FAIL: {type(ex).__name__}: {ex}")
finally:
    try: cli.close()
    except Exception: pass
