"""Read metadata and tensor statistics from a GGUF file.

Usage: python gguf-info.py <model.gguf>
"""

import struct
import sys
from collections import Counter

GGML_TYPES = {
    0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 6: "Q5_0", 7: "Q5_1",
    8: "Q8_0", 9: "Q8_1", 10: "Q2_K", 11: "Q3_K", 12: "Q4_K", 13: "Q5_K",
    14: "Q6_K", 15: "Q8_K", 16: "IQ2_XXS", 17: "IQ2_XS", 18: "IQ3_XXS",
    19: "IQ1_S", 20: "IQ4_NL", 21: "IQ3_S", 22: "IQ2_S", 23: "IQ4_XS",
    24: "I8", 25: "I16", 26: "I32", 27: "I64", 28: "F64", 29: "IQ1_M",
    30: "BF16",
}


class Reader:
    def __init__(self, fh):
        self.fh = fh

    def raw(self, n):
        data = self.fh.read(n)
        if len(data) != n:
            raise EOFError("unexpected end of file")
        return data

    def u32(self):
        return struct.unpack("<I", self.raw(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.raw(8))[0]

    def i64(self):
        return struct.unpack("<q", self.raw(8))[0]

    def string(self):
        return self.raw(self.u64()).decode("utf-8", "replace")


def read_value(r, vtype):
    if vtype == 0:
        return struct.unpack("<B", r.raw(1))[0]
    if vtype == 1:
        return struct.unpack("<b", r.raw(1))[0]
    if vtype == 2:
        return struct.unpack("<H", r.raw(2))[0]
    if vtype == 3:
        return struct.unpack("<h", r.raw(2))[0]
    if vtype == 4:
        return r.u32()
    if vtype == 5:
        return struct.unpack("<i", r.raw(4))[0]
    if vtype == 6:
        return struct.unpack("<f", r.raw(4))[0]
    if vtype == 7:
        return struct.unpack("<?", r.raw(1))[0]
    if vtype == 8:
        return r.string()
    if vtype == 9:
        etype = r.u32()
        count = r.u64()
        if count > 4096:
            # skip gigantic arrays (e.g. tokenizer vocab) but keep a marker
            for _ in range(count):
                read_value(r, etype)
            return f"<array of {count} items, type {etype}>"
        return [read_value(r, etype) for _ in range(count)]
    if vtype == 10:
        return r.u64()
    if vtype == 11:
        return r.i64()
    if vtype == 12:
        return struct.unpack("<d", r.raw(8))[0]
    raise ValueError(f"unknown value type {vtype}")


def main():
    if len(sys.argv) != 2:
        print("usage: gguf-info.py <model.gguf>")
        return 2

    with open(sys.argv[1], "rb") as fh:
        r = Reader(fh)
        magic = r.raw(4)
        if magic != b"GGUF":
            print("not a GGUF file:", magic)
            return 2
        version = r.u32()
        tensor_count = r.u64()
        kv_count = r.u64()
        print(f"GGUF version {version}, {tensor_count} tensors, {kv_count} metadata entries\n")

        meta = {}
        for _ in range(kv_count):
            key = r.string()
            vtype = r.u32()
            meta[key] = read_value(r, vtype)

        for key in sorted(meta):
            value = meta[key]
            text = str(value)
            if len(text) > 120:
                text = text[:117] + "..."
            print(f"{key} = {text}")

        print("\n--- tensor layout ---")
        types = Counter()
        total_params = 0
        for _ in range(tensor_count):
            r.string()  # name
            n_dims = r.u32()
            dims = [r.u64() for _ in range(n_dims)]
            ttype = r.u32()
            r.u64()  # offset
            count = 1
            for d in dims:
                count *= d
            total_params += count
            types[GGML_TYPES.get(ttype, f"type{ttype}")] += 1

        print("参数总量: %.1f M" % (total_params / 1e6))
        print("张量类型分布:", ", ".join(f"{k}×{v}" for k, v in types.most_common()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
