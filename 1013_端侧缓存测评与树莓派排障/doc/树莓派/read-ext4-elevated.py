#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
只读 ext4 读取器：直接从 \\.\E: （SD 卡 rootfs 分区）按偏移读取文件
用途：不装任何 ext4 驱动、不改动卡上任何数据，把关键配置导出到本地目录

用法：
  D:\\Anaconda\\python.exe -u read-ext4.py
"""

import os
import struct
import sys
import ctypes
import ctypes.wintypes as wt

DRIVE = "\\\\.\\PhysicalDrive2"
OUTDIR = r"D:\项目\树莓派\sd-extract"
PART_OFFSET = 545259520

GENERIC_READ = 0x80000000
OPEN_EXISTING = 3
FILE_SHARE_READ = 1
FILE_SHARE_WRITE = 2

_k32 = ctypes.WinDLL("kernel32", use_last_error=True)
_k32.CreateFileW.restype = ctypes.c_void_p
_k32.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                             ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
_k32.SetFilePointerEx.argtypes = [ctypes.c_void_p, ctypes.c_longlong, ctypes.c_void_p, ctypes.c_uint32]
_k32.SetFilePointerEx.restype = ctypes.c_int
_k32.ReadFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32,
                          ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p]
_k32.ReadFile.restype = ctypes.c_int
_k32.CloseHandle.argtypes = [ctypes.c_void_p]


class RawVolume:
    """裸卷读取：只读、按偏移随机读，用 Win32 API 避免 Python 文件对象的限制"""

    def __init__(self, path):
        h = _k32.CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                             None, OPEN_EXISTING, 0, None)
        if not h or h == 0xFFFFFFFFFFFFFFFF:
            err = ctypes.get_last_error()
            raise SystemExit(f"打不开 {path}: {err} ({ctypes.FormatError(err)})")
        self.h = h
        self.reads = 0
        self.bytes_read = 0

    def pread(self, off, n, base=0):
        """裸盘只允许按 512 字节扇区对齐读写，这里自动对外层请求做对齐切分
        base 用于加上分区起始偏移（超级块那次读也要加）"""
        off = base + off
        SECTOR = 512
        if n <= 0:
            return b""
        start = (off // SECTOR) * SECTOR
        end = ((off + n + SECTOR - 1) // SECTOR) * SECTOR
        if not _k32.SetFilePointerEx(self.h, start, None, 0):
            err = ctypes.get_last_error()
            raise OSError(f"SetFilePointerEx({start}) 失败: {err} {ctypes.FormatError(err)}")
        buf = ctypes.create_string_buffer(end - start)
        got = ctypes.c_uint32(0)
        if not _k32.ReadFile(self.h, buf, end - start, ctypes.byref(got), None):
            err = ctypes.get_last_error()
            raise OSError(f"ReadFile({start},{end-start}) 失败: {err} {ctypes.FormatError(err)}")
        self.reads += 1
        self.bytes_read += got.value
        data = buf.raw[:got.value]
        return data[off - start: off - start + n]

    def close(self):
        if getattr(self, "h", None):
            _k32.CloseHandle(self.h)
            self.h = None


S_IFMT = 0o170000
S_IFDIR = 0o040000
S_IFLNK = 0o120000

WANT_FILES = [
    "/etc/ssh/sshd_config",
    "/etc/nologin",
    "/etc/hosts.deny",
    "/etc/hosts.allow",
    "/etc/fail2ban/jail.local",
    "/etc/fail2ban/jail.conf",
    "/etc/ssh/sshd_config.d/rename_user.conf",
    "/etc/pam.d/sshd",
    "/etc/os-release",
    "/etc/hostname",
    "/etc/network/interfaces",
    "/etc/NetworkManager/NetworkManager.conf",
    "/etc/systemd/system/ssh.service.d/override.conf",
]
WANT_DIRS = [
    "/etc/fail2ban",
    "/etc/fail2ban/jail.d",
    "/etc/ssh/sshd_config.d",
    "/etc/ssh",
    "/etc/systemd/system/ssh.service.d",
    "/etc/network",
]


def log(m):
    print(m, flush=True)


class Ext4:
    def __init__(self, path):
        self.vol = RawVolume(path)
        self.f = self.vol
        # 读 4096 字节（整块，保证扇区对齐）拿超级块，只用到前 1024 字节
        sb = self.vol.pread(1024, 4096, base=globals().get("PART_OFFSET", 0))[:1024]
        if sb[56:58] != b"\x53\xef":
            raise SystemExit("不是 ext4 超级块（magic 不匹配）")
        self.block_size = 1024 << struct.unpack_from("<I", sb, 24)[0]
        self.blocks_per_group = struct.unpack_from("<I", sb, 32)[0]
        self.inode_size = struct.unpack_from("<H", sb, 88)[0]
        self.inodes_per_group = struct.unpack_from("<I", sb, 40)[0]
        self.first_ino = struct.unpack_from("<I", sb, 84)[0]
        self.desc_size = struct.unpack_from("<H", sb, 254)[0] or 32
        self.features_incompat = struct.unpack_from("<I", sb, 96)[0]
        self.features_ro = struct.unpack_from("<I", sb, 100)[0]
        # 组描述符表位置
        if self.block_size == 1024:
            self.gdt_off = 2 * 1024
        else:
            self.gdt_off = self.block_size
        self.file_type = bool(self.features_incompat & 0x2)
        self.extents = bool(self.features_incompat & 0x40)
        self.rec_len = bool(self.features_incompat & 0x10)
        self.dirs_64 = bool(self.features_incompat & 0x80)
        log(f"ext4: block={self.block_size} inode_size={self.inode_size} "
            f"inodes/group={self.inodes_per_group} desc_size={self.desc_size} "
            f"extents={self.extents} filetype={self.file_type} 64bit={self.dirs_64}")

    # ---------- 低层读 ----------
    def read_at(self, off, n):
        return self.vol.pread(off, n, base=globals().get("PART_OFFSET", 0))

    def group_desc(self, g):
        raw = self.read_at(self.gdt_off + g * self.desc_size, self.desc_size)
        blk_bm = struct.unpack_from("<I", raw, 0)[0]
        ino_bm = struct.unpack_from("<I", raw, 4)[0]
        itab = struct.unpack_from("<I", raw, 8)[0]
        return blk_bm, ino_bm, itab

    def inode(self, ino):
        g = (ino - 1) // self.inodes_per_group
        i = (ino - 1) % self.inodes_per_group
        _, _, itab = self.group_desc(g)
        off = itab * self.block_size + i * self.inode_size
        raw = self.read_at(off, self.inode_size)
        mode = struct.unpack_from("<H", raw, 0)[0]
        size = struct.unpack_from("<I", raw, 4)[0]
        size_hi = struct.unpack_from("<I", raw, 108)[0] if self.inode_size > 108 else 0
        size = size | (size_hi << 32)
        block = list(struct.unpack_from("<15I", raw, 40))
        return {"mode": mode, "size": size, "block": block, "raw": raw}

    # ---------- 块映射 ----------
    def extents_of(self, node, depth):
        """解析 extent 树节点（12 字节一项），返回 [(logical, phys, count)]"""
        out = []
        entries = struct.unpack_from("<H", node, 2)[0]
        for k in range(entries):
            off = 12 + k * 12
            if depth == 0:
                ee_block, ee_len, start_hi, start_lo = struct.unpack_from("<IHHI", node, off)
                out.append((ee_block, (start_hi << 32) | start_lo, ee_len & 0x7FFF))
            else:
                ei_block, leaf_lo, leaf_hi = struct.unpack_from("<IIH", node, off)
                leaf = (leaf_hi << 32) | leaf_lo
                child = self.read_at(leaf * self.block_size, self.block_size)
                out.extend(self.extents_of(child, depth - 1))
        return out

    def map_blocks(self, inode):
        """返回 (extent 列表, 间接块映射列表)"""
        if self.extents and (inode["block"][0] & 0xFFFF) == 0xF30A:
            node = inode["raw"][40:40 + 60]
            depth = struct.unpack_from("<H", node, 6)[0]
            return self.extents_of(node, depth), []
        # 老式块映射
        ptrs = []
        bs = self.block_size
        per = bs // 4
        for idx in range(12):
            if inode["block"][idx]:
                ptrs.append((idx, inode["block"][idx]))
        ind = [inode["block"][12], inode["block"][13], inode["block"][14]]
        for lvl, blk in enumerate(ind):
            if not blk:
                continue
            data = self.read_at(blk * bs, bs)
            arr = struct.unpack_from("<%dI" % per, data, 0)
            for k, p in enumerate(arr):
                if p:
                    ptrs.append((12 + lvl * per + k, p))
        ptrs.sort()
        return [], ptrs

    def size_of_blockmap(self, mapping):
        total = 0
        for _, _, n in mapping:
            total += n
        return total

    def read_file(self, ino):
        inode = self.inode(ino)
        size = inode["size"]
        ext, ptrs = self.map_blocks(inode)
        out = bytearray()
        if ext:
            for _, phys, n in ext:
                out += self.read_at(phys * self.block_size, n * self.block_size)
        else:
            for _, phys in ptrs:
                out += self.read_at(phys * self.block_size, self.block_size)
        return bytes(out[:size])

    # ---------- 目录 ----------
    def list_dir(self, ino, max_blocks=64):
        raw = self.read_file(ino)
        entries = []
        pos = 0
        while pos + 8 <= len(raw):
            ino_n, rec_len, name_len = struct.unpack_from("<IHB", raw, pos)
            ftype = raw[pos + 7] if self.file_type else 0
            name = raw[pos + 8:pos + 8 + name_len]
            if ino_n and name not in (b".", b".."):
                entries.append((name.decode("utf-8", "replace"), ino_n, ftype))
            if rec_len == 0:
                break
            pos += rec_len
        return entries

    def lookup(self, path):
        """按路径查 inode 号，逐级用 dir 索引节点找"""
        ino = 2  # 根目录
        parts = [p for p in path.split("/") if p]
        for i, part in enumerate(parts):
            try:
                entries = self.list_dir(ino)
            except Exception as e:
                raise SystemExit(f"列目录失败 {path} (在 {part} 处): {e}")
            found = None
            for name, n, ft in entries:
                if name == part:
                    found = n
                    break
            if found is None:
                # 可能是 htree 索引目录：退化为全盘扫描不可行，直接报缺
                return None, entries
            ino = found
        return ino, None


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    fs = Ext4(DRIVE)
    log("")

    # 1) 关键文件
    for path in WANT_FILES:
        try:
            ino, _ = fs.lookup(path)
            if ino is None:
                log(f"[缺失] {path}")
                continue
            inode = fs.inode(ino)
            mode = inode["mode"]
            if (mode & S_IFMT) == S_IFLNK:
                target = fs.read_file(ino).decode("utf-8", "replace")
                log(f"[符号链接] {path} -> {target}")
                continue
            data = fs.read_file(ino)
            dest = os.path.join(OUTDIR, path.replace("/", "_").lstrip("_"))
            with open(dest, "wb") as fo:
                fo.write(data)
            log(f"[导出] {path}  {len(data)} 字节 -> {dest}")
        except SystemExit:
            raise
        except Exception as e:
            log(f"[出错] {path}: {type(e).__name__}: {e}")

    # 2) 关键目录内容
    log("")
    for d in WANT_DIRS:
        try:
            ino, _ = fs.lookup(d)
            if ino is None:
                log(f"[目录缺失] {d}")
                continue
            entries = fs.list_dir(ino)
            log(f"[目录] {d}  共 {len(entries)} 项: " + ", ".join(n for n, _, _ in entries))
        except Exception as e:
            log(f"[目录出错] {d}: {type(e).__name__}: {e}")

    log("")
    log(f"完成，导出目录: {OUTDIR}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("已中断")
    except SystemExit as e:
        log(str(e))
        sys.exit(1)
    except Exception as e:
        log(f"致命错误: {type(e).__name__}: {e}")
        sys.exit(1)
