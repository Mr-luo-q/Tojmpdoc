#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 解析 GGUF 元数据，对比四个模型的架构差异
#
# 为什么需要这个：
#   llama-cli 加载模型时只打印少量摘要（实际只看到 ftype 一行），
#   拿不到层数、注意力头数、KV 头数（GQA 比例）等关键结构参数。
#   而这些正是用户关心的"模型结构本身有区别"的具体体现。
#
#   GGUF 是自描述格式：文件头之后是元数据键值对，全部明文可读。
#   所以直接解析文件即可，不需要任何外部工具。
#
# GGUF 格式概要（本脚本实现的读取逻辑）：
#   magic       4 字节  "GGUF"
#   version     uint32
#   n_tensors   uint64
#   n_kv        uint64
#   然后是 n_kv 个键值对：
#     key         gguf_string（uint64 长度 + UTF-8 字节）
#     value_type  uint32（枚举，见下）
#     value       按类型读取
#
#   值类型枚举：
#     0 uint8  1 int8  2 uint16  3 int16  4 uint32  5 int32
#     6 float32 7 bool 8 string  9 array  10 uint64 11 int64 12 float64
#
# 用法：
#   bash termux-gguf-arch.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

LOG="$HOME/gguf-arch.log"
exec > "$LOG" 2>&1

cat > "$TMPDIR/gguf_arch.py" <<'PY'
"""解析 GGUF 元数据，输出架构相关字段。"""
import struct
import sys

# 只关心这些键（架构差异的集中体现）
WANT_PREFIX = ("general.architecture", "general.name", "general.size_label")
WANT_SUFFIX = (
    ".block_count", ".context_length", ".embedding_length",
    ".feed_forward_length", ".attention.head_count",
    ".attention.head_count_kv", ".attention.key_length",
    ".attention.value_length", ".attention.layer_norm_rms_epsilon",
    ".rope.freq_base", ".rope.dimension_count",
    ".attention.sliding_window", ".attention.logit_scale",
    ".expert_count", ".expert_used_count",
    ".ssm.state_size", ".ssm.group_count", ".ssm.time_step_rank",
    ".ssm.conv_kernel", ".full_attention_interval",
    ".attn_logit_softcapping", ".final_logit_softcapping",
    ".vocab_size", ".tensor_data_layout",
)

T_UINT8, T_INT8, T_UINT16, T_INT16 = 0, 1, 2, 3
T_UINT32, T_INT32, T_FLOAT32, T_BOOL = 4, 5, 6, 7
T_STRING, T_ARRAY, T_UINT64, T_INT64, T_FLOAT64 = 8, 9, 10, 11, 12

FMT = {
    T_UINT8: ("<B", 1), T_INT8: ("<b", 1),
    T_UINT16: ("<H", 2), T_INT16: ("<h", 2),
    T_UINT32: ("<I", 4), T_INT32: ("<i", 4),
    T_FLOAT32: ("<f", 4), T_BOOL: ("<?", 1),
    T_UINT64: ("<Q", 8), T_INT64: ("<q", 8), T_FLOAT64: ("<d", 8),
}


def rd(f, fmt):
    """按格式读一个值，返回 (值, 原始字节)"""
    size = struct.calcsize(fmt)
    b = f.read(size)
    if len(b) < size:
        raise EOFError(f"读 {fmt} 时 EOF")
    return struct.unpack(fmt, b)[0], b


def rd_str(f):
    """gguf_string = uint64 长度 + UTF-8 数据"""
    n, _ = rd(f, "<Q")
    if n > 10_000_000:
        raise ValueError(f"字符串长度异常: {n}")
    return f.read(n).decode("utf-8", errors="replace")


def rd_value(f, t):
    """读一个任意类型的值"""
    if t == T_STRING:
        return rd_str(f)
    if t == T_ARRAY:
        et, _ = rd(f, "<I")
        n, _ = rd(f, "<Q")
        # 数组只统计长度，不展开（词表数组可能上百万项）
        if et == T_STRING:
            for _ in range(n):
                rd_str(f)
            return f"<array of {n} strings>"
        if et in FMT:
            fmt, size = FMT[et]
            f.read(size * n)
            return f"<array of {n} scalar>"
        if et == T_ARRAY:
            return "<nested array, skipped>"
        raise ValueError(f"未知数组元素类型 {et}")
    if t in FMT:
        fmt, _ = FMT[t]
        v, _ = rd(f, fmt)
        return v
    raise ValueError(f"未知值类型 {t}")


def parse(path):
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic != b"GGUF":
            return {"error": f"magic 不是 GGUF: {magic!r}"}
        version, _ = rd(f, "<I")
        n_tensors, _ = rd(f, "<Q")
        n_kv, _ = rd(f, "<Q")

        out = {"_version": version, "_n_tensors": n_tensors, "_n_kv": n_kv}
        for _ in range(n_kv):
            key = rd_str(f)
            vt, _ = rd(f, "<I")
            val = rd_value(f, vt)
            # 只保留关心的键
            if key.startswith(WANT_PREFIX) or key.endswith(WANT_SUFFIX):
                out[key] = val
        return out


if __name__ == "__main__":
    for path in sys.argv[1:]:
        print("=" * 62)
        print(" " + path.split("/")[-1])
        print("=" * 62)
        try:
            d = parse(path)
        except Exception as e:
            print(f"  解析失败: {type(e).__name__}: {e}")
            print()
            continue

        if "error" in d:
            print("  " + d["error"])
            print()
            continue

        print(f"  GGUF 版本 {d['_version']}   张量数 {d['_n_tensors']}   元数据条目 {d['_n_kv']}")
        print()
        for k in sorted(d):
            if k.startswith("_"):
                continue
            v = d[k]
            # 长浮点截断显示
            if isinstance(v, float):
                v = f"{v:.6g}"
            print(f"    {k:52s} {v}")
        print()
PY

echo "解析开始: $(date '+%H:%M:%S')"
echo

python "$TMPDIR/gguf_arch.py" \
  "$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" \
  "$HOME/models/Qwen3-0.6B-Q4_K_M.gguf" \
  "$HOME/models/Qwen3-1.7B-Q4_K_M.gguf" \
  "$HOME/models/Qwen3.5-2B-Q4_K_M.gguf" 2>&1

echo "完成: $(date '+%H:%M:%S')"
echo "日志: $LOG"
