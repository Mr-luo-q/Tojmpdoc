"""校验提速实测打包结果的完整性。

做三件事：
  1. 逐条目比对 SHA-256：把 zip 里的内容与磁盘上的源文件直接比，确认打包没改动任何字节
  2. 校验 清单.tsv：确认清单覆盖的条目与实际条目一致，且清单里的哈希可复算
  3. CRC 全量校验：testzip() 检查每个条目的压缩数据是否完整

比仓库里其他打包脚本多做第 1 步 —— 那两个只做了 CRC 校验与文件名检查，
「解压出来和原文件是不是一模一样」这一步此前没有直接验证过。

用法：
  python tools/verify-speed-test-zip.py <项目目录> [zip 路径]
  不给 zip 路径时，自动取项目目录下最新的 *20261014.zip
"""
import hashlib
import importlib.util
import sys
import zipfile
from pathlib import Path


def load_packer(root):
    """按路径载入打包脚本，复用它的清单规则，避免两处各写一份文件列表。"""
    spec = importlib.util.spec_from_file_location("make_speed_test_zip", root / "tools" / "make-speed-test-zip.py")
    module = importlib.util.module_from_spec(spec)
    saved = sys.argv
    sys.argv = ["make-speed-test-zip.py", str(root), "unused.zip"]
    try:
        spec.loader.exec_module(module)
    finally:
        sys.argv = saved
    return module


def sha256(data):
    """计算字节串的 SHA-256，用于逐字节比对。"""
    return hashlib.sha256(data).hexdigest()


def main():
    """命令行入口：加载清单、逐项比对、输出结论。"""
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if len(sys.argv) > 2:
        archive = Path(sys.argv[2])
    else:
        candidates = list(root.glob("*20261014.zip"))
        if not candidates:
            print("FAILED: 找不到 20261014 结尾的 zip，请显式给出路径")
            return 1
        archive = max(candidates, key=lambda p: p.stat().st_mtime)

    packer = load_packer(root)
    source_map = dict(packer.build_manifest())

    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        crc_bad = z.testzip()

        # 第一步：逐条目与源文件比哈希
        mismatch, compared, missing_in_zip = [], 0, []
        for arcname, path in source_map.items():
            if arcname not in names:
                missing_in_zip.append(arcname)
                continue
            if sha256(z.read(arcname)) != sha256(path.read_bytes()):
                mismatch.append(arcname)
            compared += 1

        # 第二步：清单.tsv 是否覆盖全部内容条目，且哈希可复算
        manifest_bad = []
        manifest_entries = set()
        for line in z.read("清单.tsv").decode("utf-8").splitlines()[1:]:
            arcname, size, digest = line.split("\t")
            manifest_entries.add(arcname)
            data = z.read(arcname)
            if len(data) != int(size) or sha256(data) != digest:
                manifest_bad.append(arcname)
        expected = names - {"说明.txt", "清单.tsv"}

    print(f"archive={archive.name}")
    print(f"entries={len(names)} compared={compared}")
    print(f"crc={crc_bad or 'OK'}")
    print(f"sha256_mismatch={mismatch}")
    print(f"missing_in_zip={missing_in_zip}")
    print(f"manifest_coverage_ok={manifest_entries == expected}")
    print(f"manifest_hash_bad={manifest_bad}")
    ok = not (crc_bad or mismatch or missing_in_zip or manifest_bad) and manifest_entries == expected
    print("RESULT=" + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
