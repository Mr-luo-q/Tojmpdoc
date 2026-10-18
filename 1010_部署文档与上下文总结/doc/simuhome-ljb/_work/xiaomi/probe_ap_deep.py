r"""连上设备配网热点后，把它彻底探一遍——目标是判断"能不能不走米家控制它"。

依次做：
  1 打印本机地址（判断设备网段）
  2 TCP 连接扫描 /24 的几个 IoT 常用端口，找活跃主机
  3 miIO 发现（UDP 224.0.0.50:54321）—— 小米系设备会回应
  4 Tuya 发现（UDP 广播 6666 / 6667）—— 涂鸦系设备会回应
  5 SSDP M-SEARCH（239.255.255.250:1900）—— 找 UPnP/局域网页
  6 mDNS 服务枚举（224.0.0.251:5353）
  7 打印 ARP 邻居表，看哪些主机真的应答过

只读，不写任何设备状态。

用法：
  python _work\xiaomi\probe_ap_deep.py            # 自动扫本机所在的 192.168 网段
  python _work\xiaomi\probe_ap_deep.py 192.168.31 # 指定网段（设备入网后扫家用网段）
"""

import socket
import struct
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

SCAN_PORTS = (80, 443, 81, 8080, 8443, 54321, 6668, 9999, 22, 23)
MIOT_MAGIC = bytes.fromhex("21310020" + "ffffffff" * 6)


def local_ipv4() -> list[str]:
    """本机所有非回环 IPv4。"""

    addresses = set()
    for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
        addresses.add(info[4][0])
    return sorted(addresses)


def probe_tcp(host: str, port: int, timeout: float = 0.4) -> bool:
    """探测一个 TCP 端口是否可连。"""

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        return sock.connect_ex((host, port)) == 0


def scan_subnet(prefix: str) -> list[tuple[str, int]]:
    """扫整个 /24，返回命中的 (host, port)。"""

    targets = [(f"{prefix}.{index}", port) for index in range(1, 255) for port in SCAN_PORTS]
    hits: list[tuple[str, int]] = []
    with ThreadPoolExecutor(max_workers=160) as pool:
        for (host, port), ok in zip(targets, pool.map(lambda item: probe_tcp(*item), targets)):
            if ok:
                hits.append((host, port))
    return hits


def udp_probe(payload: bytes, target: tuple[str, int], seconds: float = 4.0) -> list[tuple[str, bytes]]:
    """发一个 UDP 包，收一段时间内的所有应答。"""

    answers: list[tuple[str, bytes]] = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.settimeout(0.5)
        try:
            sock.sendto(payload, target)
        except OSError as error:
            print(f"  发包失败：{error}")
            return answers
        deadline = time.time() + seconds
        while time.time() < deadline:
            try:
                data, address = sock.recvfrom(4096)
            except socket.timeout:
                continue
            answers.append((address[0], data))
    return answers


def ssdp_search() -> list[tuple[str, bytes]]:
    """SSDP M-SEARCH。"""

    message = (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 2\r\n"
        "ST: ssdp:all\r\n\r\n"
    ).encode()
    return udp_probe(message, ("239.255.255.250", 1900), seconds=4.0)


def mdns_query() -> list[tuple[str, bytes]]:
    """一条最简的 mDNS 查询（问 _services._dns-sd._udp.local）。"""

    name = b"\x09_services\x07_dns-sd\x04_udp\x05local\x00"
    payload = struct.pack(">HHHHHH", 0, 0, 1, 0, 0, 0) + name + struct.pack(">HH", 12, 1)
    return udp_probe(payload, ("224.0.0.251", 5353), seconds=4.0)


def hap_query() -> list[tuple[str, bytes]]:
    """专门问 HomeKit（_hap._tcp.local）。

    如果这盏灯同时支持 HomeKit，HA 的 homekit_controller 集成能直接配对，
    纯本地、不需要云、也不需要 token——那是最理想的"不通过米家"方案。
    """

    name = b"\x04_hap\x04_tcp\x05local\x00"
    payload = struct.pack(">HHHHHH", 0, 0, 1, 0, 0, 0) + name + struct.pack(">HH", 12, 1)
    return udp_probe(payload, ("224.0.0.251", 5353), seconds=4.0)


def arp_table() -> None:
    """打印 ARP 邻居表。"""

    try:
        output = subprocess.run(
            ["arp", "-a"], capture_output=True, text=True, timeout=20,
            encoding="gbk", errors="replace",
        ).stdout
    except OSError as error:
        print(f"  取 ARP 表失败：{error}")
        return
    for line in output.splitlines():
        if "192.168." in line and "ff-ff-ff" not in line.lower():
            print("  " + line.strip())


def main() -> int:
    print("== 1 本机地址 ==")
    addresses = [address for address in local_ipv4() if not address.startswith("127.")]
    for address in addresses:
        print("  " + address)
    if len(sys.argv) > 1:
        prefixes = [sys.argv[1]]
        print(f"  （按参数指定网段：{prefixes[0]}.0/24）")
    else:
        prefixes = sorted(
            {address.rsplit(".", 1)[0] for address in addresses if address.startswith("192.168.")}
        )

    print("\n== 2 TCP 扫描（/24 的常用 IoT 端口）==")
    for prefix in prefixes:
        hits = scan_subnet(prefix)
        if hits:
            for host, port in sorted(hits):
                print(f"  开放 {host}:{port}")
        else:
            print(f"  {prefix}.0/24：没有开放端口的主机")

    print("\n== 3 miIO 发现（224.0.0.50:54321）==")
    miot = udp_probe(MIOT_MAGIC, ("224.0.0.50", 54321))
    if not miot:
        print("  没有设备应答")
    for address, data in miot:
        did = struct.unpack(">I", data[8:12])[0] if len(data) >= 12 else "?"
        print(f"  {address} 回应，device_id={did}")

    print("\n== 4 Tuya 发现（广播 6666 / 6667）==")
    tuya = []
    for port in (6666, 6667):
        tuya += udp_probe(b"\x00\x00\x55\xaa", ("255.255.255.255", port), seconds=3.0)
    if not tuya:
        print("  没有设备应答")
    for address, data in tuya:
        print(f"  {address} 应答（{len(data)} 字节）")

    print("\n== 5 SSDP ==")
    ssdp = ssdp_search()
    if not ssdp:
        print("  没有设备应答")
    for address, data in ssdp:
        first = data.decode("utf-8", "replace").splitlines()
        print(f"  {address}: {first[0] if first else ''}")

    print("\n== 6 mDNS ==")
    mdns = mdns_query()
    if not mdns:
        print("  没有设备应答")
    for address, data in mdns:
        print(f"  {address} 回了 {len(data)} 字节")

    print("\n== 7 HomeKit（_hap._tcp）==")
    hap = hap_query()
    if not hap:
        print("  没有设备应答（不一定是坏事，很多设备默认不广播）")
    for address, data in hap:
        print(f"  {address} 回了 {len(data)} 字节 —— 支持 HomeKit！")

    print("\n== 8 ARP 邻居表 ==")
    arp_table()

    print("\n== 9 设备 HTTP 首页（如果有活跃主机）==")
    hosts = sorted({host for host, _ in scan_subnet(prefixes[0])}) if prefixes else []
    for host in hosts:
        for scheme in ("http", "https"):
            try:
                with socket.create_connection((host, 80 if scheme == "http" else 443), timeout=1.5) as sock:
                    sock.sendall(f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode())
                    head = sock.recv(400).decode("utf-8", "replace").splitlines()
                print(f"  {scheme}://{host} -> {head[0] if head else ''}")
            except OSError:
                continue
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
