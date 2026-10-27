"""唤协调器：只试 ZNP 复位/握手与 TI BSL 同步，带写超时，逐组合打印进度。"""
import time

import serial

PORT = "COM7"


def mt(cmd0: int, cmd1: int, data: bytes = b"") -> bytes:
    """拼一帧 ZNP（MT）报文。"""
    body = bytes([cmd0, cmd1]) + data
    fcs = 0
    for byte in bytes([len(body)]) + body:
        fcs ^= byte
    return bytes([0xFE, len(body)]) + body + bytes([fcs])


def read_all(ser, seconds: float) -> bytes:
    """收一段时间内的所有数据。"""
    end = time.time() + seconds
    buf = bytearray()
    while time.time() < end:
        chunk = ser.read(ser.in_waiting or 1)
        if chunk:
            buf.extend(chunk)
            end = time.time() + 0.25
    return bytes(buf)


def try_combo(baud: int, dtr: bool, rts: bool) -> None:
    """在一个波特率与线状态下依次发复位、PING、BSL 同步，打印收到的任何字节。"""
    try:
        ser = serial.Serial()
        ser.port = PORT
        ser.baudrate = baud
        ser.timeout = 0.15
        ser.write_timeout = 1.0          # 关键：没有流控时避免写阻塞
        ser.rtscts = False
        ser.dsrdtr = False
        ser.dtr = dtr
        ser.rts = rts
        ser.open()
    except Exception as exc:
        print(f"[{baud} dtr={dtr} rts={rts}] open failed {type(exc).__name__}", flush=True)
        return
    try:
        time.sleep(0.2)
        ser.reset_input_buffer()
        heard = read_all(ser, 0.5)
        ser.write(mt(0x41, 0x00, b"\x01"))       # SYS_RESET_REQ
        r1 = read_all(ser, 0.7)
        ser.write(mt(0x21, 0x01))                 # SYS_PING
        r2 = read_all(ser, 0.7)
        ser.write(mt(0x21, 0x06))                 # SYS_VERSION
        r3 = read_all(ser, 0.7)
        ser.write(b"\x55\x55")                    # TI BSL 同步（0x55 0x55）
        bsl1 = read_all(ser, 0.5)
        ser.write(b"\xcc\x33\xee")
        bsl2 = read_all(ser, 0.5)
        got = any((heard, r1, r2, r3, bsl1, bsl2))
        print(f"[{baud} dtr={dtr} rts={rts}] boot={heard.hex(' ') or '-'} reset={r1.hex(' ') or '-'} "
              f"ping={r2.hex(' ') or '-'} ver={r3.hex(' ') or '-'} bsl={bsl1.hex(' ') or '-'}/{bsl2.hex(' ') or '-'}",
              flush=True)
    finally:
        ser.close()


for baud in (115200, 57600):
    for dtr in (False, True):
        for rts in (False, True):
            try_combo(baud, dtr, rts)

print("probe finished", flush=True)
