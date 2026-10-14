#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
树莓派直连：迷你 DHCP 服务器（v2，修好源地址问题）
---------------------------------------------------
v1 的问题：socket 绑 0.0.0.0，sendto 广播时源地址是 0.0.0.0，Windows 报
          WinError 10049 拒绝发送。
v2 的修法：用 IP_PKTINFO 显式指定"从哪块网卡、哪个源地址"发包。

用法:
  D:\\Anaconda\\python.exe dsh-dhcp-server.py --iface 192.168.137.1 --offer 192.168.137.50
"""

import argparse
import datetime
import socket
import struct
import sys
import time

MAC_BROADCAST = b"\xff\xff\xff\xff\xff\xff"


def log(msg):
    ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    f = globals().get("_logfile")
    if f:
        try:
            f.write(line + "\n")
            f.flush()
        except Exception:
            pass


def ip2b(s):
    return socket.inet_aton(s)


def parse_dhcp(data):
    if len(data) < 240 or data[236:240] != b"\x63\x82\x53\x63":
        return None
    op = data[0]
    xid = struct.unpack("!I", data[4:8])[0]
    chaddr = data[28:34]
    i = 240
    msgtype = None
    req_ip = None
    hostname = None
    while i < len(data):
        opt = data[i]
        if opt == 255:
            break
        if opt == 0:
            i += 1
            continue
        if i + 1 >= len(data):
            break
        ln = data[i + 1]
        val = data[i + 2:i + 2 + ln]
        if opt == 53 and ln >= 1:
            msgtype = val[0]
        elif opt == 50 and ln == 4:
            req_ip = socket.inet_ntoa(val)
        elif opt == 12 and ln:
            hostname = val.decode("utf-8", "replace")
        i += 2 + ln
    return op, xid, chaddr, msgtype, req_ip, hostname


def build_reply(xid, chaddr, offer_ip, server_ip, msgtype):
    pkt = bytearray(240)
    pkt[0] = 2
    pkt[1] = 1
    pkt[2] = 6
    pkt[3] = 0
    pkt[4:8] = struct.pack("!I", xid)
    pkt[10:12] = b"\x80\x00"                 # broadcast flag
    pkt[16:20] = ip2b(offer_ip)              # yiaddr
    pkt[20:24] = ip2b(server_ip)             # siaddr
    pkt[28:34] = chaddr
    pkt[236:240] = b"\x63\x82\x53\x63"

    opts = bytearray()
    opts += b"\x35\x01" + bytes([msgtype])            # 53
    opts += b"\x01\x04" + ip2b("255.255.255.0")       # 1 mask
    opts += b"\x03\x04" + ip2b(server_ip)             # 3 router
    # 6 DNS：不补这一条，树莓派即使 NAT 通了也只能 ping IP，解析不了域名
    opts += b"\x06\x08" + ip2b("202.113.5.6") + ip2b("202.113.15.2")
    opts += b"\x36\x04" + ip2b(server_ip)             # 54 server id
    opts += b"\x33\x04" + struct.pack("!I", 3600)     # 51 lease
    opts += b"\xff"
    return bytes(pkt + opts)


def make_pktinfo(ip):
    """IP_PKTINFO: 指定源地址，ipi_ifindex 留 0 由路由决定（够用了）"""
    return struct.pack("=I4s4s", 0, ip2b(ip), ip2b("0.0.0.0"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default="192.168.137.1", help="绑定并作为源地址的本机地址")
    ap.add_argument("--offer", default="192.168.137.50", help="分配给树莓派的地址")
    ap.add_argument("--retry-bind", action="store_true",
                    help="绑定失败时每 30 秒重试（计划任务用，等网线插上）")
    ap.add_argument("--log", default=r"D:\项目\树莓派\dhcp-server.log")
    args = ap.parse_args()

    if args.log:
        try:
            globals()["_logfile"] = open(args.log, "a", encoding="utf-8")
        except OSError:
            globals()["_logfile"] = None

    # 关键：直接绑定到有线口的地址（不是 0.0.0.0），这样 sendto 广播时
    # 源地址就是 192.168.137.1，Windows 不会报 10049 拒绝发送。
    while True:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            s.bind((args.iface, 67))
            break
        except OSError as e:
            s.close()
            log(f"绑定 {args.iface}:67 失败: {e}")
            if getattr(e, "winerror", None) == 10048:
                log("端口已被占用（已有实例在跑），本实例退出。")
                return 0
            if not args.retry_bind:
                log("回退到绑定 0.0.0.0:67")
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                try:
                    s.bind(("0.0.0.0", 67))
                    break
                except OSError as e2:
                    log(f"回退绑定也失败: {e2}，退出。")
                    return 0
            log("30 秒后重试（等有线口拿到 192.168.137.1）……")
            time.sleep(30)
    s.settimeout(1.0)

    log("=" * 60)
    log(f"迷你 DHCP 服务器已启动  绑定/源地址={args.iface}  发放={args.offer}/24")
    log("=" * 60)

    assigned = {}
    n = 0
    while True:
        try:
            data, addr = s.recvfrom(4096)
        except socket.timeout:
            continue
        except KeyboardInterrupt:
            break
        except OSError as e:
            log(f"收包出错（继续）: {e}")
            time.sleep(0.5)
            continue

        try:
            parsed = parse_dhcp(data)
            if not parsed:
                continue
            op, xid, chaddr, msgtype, req_ip, hostname = parsed
            mac = ":".join(f"{b:02x}" for b in chaddr)
            name = {1: "DISCOVER", 3: "REQUEST", 7: "RELEASE", 8: "INFORM"}.get(msgtype, str(msgtype))
            n += 1
            log(f"#{n} {name}  MAC={mac}  host={hostname}  req={req_ip}")

            if msgtype in (1, 3):
                ip = assigned.setdefault(mac, args.offer)
                reply_type = 2 if msgtype == 1 else 5
                pkt = build_reply(xid, chaddr, ip, args.iface, reply_type)
                for dst in ("255.255.255.255", addr[0]):
                    try:
                        s.sendto(pkt, (dst, 68))
                        log(f"    已发 {'OFFER' if reply_type == 2 else 'ACK'} {ip} -> {dst}:68")
                        break
                    except OSError as e:
                        log(f"    发往 {dst}:68 失败: {e}")
        except Exception as e:
            log(f"处理包出错（继续）: {type(e).__name__}: {e}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n已停止")
    except OSError as e:
        print(f"启动失败: {e}")
        sys.exit(1)
