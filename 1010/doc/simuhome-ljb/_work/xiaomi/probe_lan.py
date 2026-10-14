r"""在局域网里探小米设备（miIO 的 UDP 发现协议）。

原理：往 224.0.0.50:54321 发一个固定的 hello 包，支持 miIO 的设备会单播回一个应答，
里面带设备 id。用来判断"设备能不能本地直连"——这决定了能不能不走云。

只读：只发发现包，不写任何设备状态。
用法：python _work\xiaomi\probe_lan.py
"""

import socket
import struct
import time

DISCOVERY_TARGET = ("224.0.0.50", 54321)
HELLO = bytes.fromhex("21310020" + "ffffffff" * 6)
LISTEN_SECONDS = 6


def main() -> int:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    sock.settimeout(1.0)
    sock.bind(("", 0))
    sock.sendto(HELLO, DISCOVERY_TARGET)

    seen: dict[str, int] = {}
    deadline = time.time() + LISTEN_SECONDS
    while time.time() < deadline:
        try:
            data, address = sock.recvfrom(1024)
        except socket.timeout:
            continue
        if len(data) < 32 or data[:2] != b"\x21\x31":
            continue
        did = struct.unpack(">I", data[8:12])[0]
        seen[address[0]] = did

    sock.close()
    if not seen:
        print("没有任何设备应答——这些设备都是纯云的，本地直连走不通。")
        return 0

    print(f"有 {len(seen)} 台设备在局域网上应答：")
    for ip, did in seen.items():
        print(f"  {ip:<16} device_id={did}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
