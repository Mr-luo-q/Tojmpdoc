"""Write a (optionally .xz-compressed) disk image straight to a raw Windows device.

Usage: python raw-write.py <image-file> <device-path>
Example: python raw-write.py C:\\img.xz \\\\.\\PhysicalDrive2
"""

import ctypes
import ctypes.wintypes as w
import lzma
import os
import sys
import time

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
FILE_SHARE_READ = 1
FILE_SHARE_WRITE = 2
OPEN_EXISTING = 3
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
CHUNK = 4 * 1024 * 1024

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.CreateFileW.argtypes = [
    w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p,
    w.DWORD, w.DWORD, ctypes.c_void_p,
]
k32.CreateFileW.restype = w.HANDLE
k32.WriteFile.argtypes = [
    w.HANDLE, ctypes.c_void_p, w.DWORD, ctypes.POINTER(w.DWORD), ctypes.c_void_p,
]
k32.WriteFile.restype = w.BOOL
k32.CloseHandle.argtypes = [w.HANDLE]
k32.CloseHandle.restype = w.BOOL


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: raw-write.py <image> <device>")
        return 2

    src, dst = sys.argv[1], sys.argv[2]
    if not os.path.exists(src):
        print("image not found:", src)
        return 2

    handle = k32.CreateFileW(
        dst,
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        None,
        OPEN_EXISTING,
        0,
        None,
    )
    if handle == INVALID_HANDLE_VALUE:
        print("open failed, win32 error:", ctypes.get_last_error())
        return 3

    opener = lzma.open if src.lower().endswith(".xz") else open
    written = 0
    started = time.time()
    try:
        with opener(src, "rb") as fin:
            while True:
                data = fin.read(CHUNK)
                if not data:
                    break
                # keep every write sector aligned except the very last one
                if len(data) % 512:
                    data += b"\0" * (512 - len(data) % 512)
                buf = ctypes.create_string_buffer(data, len(data))
                done = w.DWORD(0)
                ok = k32.WriteFile(handle, buf, len(data), ctypes.byref(done), None)
                if not ok:
                    print("write failed at offset", written, "win32 error:", ctypes.get_last_error())
                    return 4
                written += done.value
                if written % (256 * 1024 * 1024) < CHUNK:
                    elapsed = max(time.time() - started, 0.001)
                    print(
                        "%.0f MB  %.1f MB/s" % (written / 1048576, written / 1048576 / elapsed),
                        flush=True,
                    )
    finally:
        k32.CloseHandle(handle)

    elapsed = max(time.time() - started, 0.001)
    print("done: %.0f MB in %.1f s (%.1f MB/s)" % (written / 1048576, elapsed, written / 1048576 / elapsed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
