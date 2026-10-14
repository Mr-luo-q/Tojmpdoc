#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · NPU 验证：用 TFLite 内置的 NNAPI delegate 跑真实模型
#
# 为什么换这条路：
#   之前用 NNAPI 的 C API 手工建图，卡在 ANeuralNetworksOperandType 的
#   ABI 上（四种结构体布局、两种类型常量全返回 BAD_DATA=4），
#   而准确的 NDK 头文件在 Termux 里没有、网上也取不到。
#
#   但 TFLite 的 C++ 库通常把 NnApiDelegate 编进去了，
#   用 Python 的 tf.lite.Interpreter(experimental_delegates=[...])
#   就能直接用，不需要手工拼结构体。
#
# 本脚本做：
#   1. 用 TFLite 造一个最小模型（CONV 或 FULLY_CONNECTED）
#   2. 先纯 CPU 跑，记录耗时与结果
#   3. 再挂 NNAPI delegate 跑，对比结果与耗时
#   4. 若 NNAPI 报错，把错误原文打出来（这是判断可用性的直接证据）
#
# 用法：
#   bash termux-npu-tflite.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

RESULT="$HOME/npu-tflite.log"
: > "$RESULT"
say() { echo "$@" | tee -a "$RESULT"; }

say "=============================================================="
say " 环境"
say "=============================================================="
python -c "import tflite_runtime, sys; print('tflite_runtime ok, python', sys.version.split()[0])" 2>&1 | tee -a "$RESULT"
python -c "import numpy; print('numpy', numpy.__version__)" 2>&1 | tee -a "$RESULT"

say ""
say "=============================================================="
say " 一、TFLite 里有哪些 delegate 相关符号"
say "=============================================================="
python - <<'PY' 2>&1 | tee -a "$RESULT"
import tflite_runtime.interpreter as tflite
print("tflite_runtime 模块属性:")
for n in dir(tflite):
    if not n.startswith('_'):
        print("   ", n)
print()
print("Interpreter 构造参数:")
import inspect
try:
    sig = inspect.signature(tflite.Interpreter.__init__)
    for p in sig.parameters.values():
        print("   ", p.name, "=", p.default)
except Exception as e:
    print("拿不到签名:", e)
PY

say ""
say "=============================================================="
say " 二、用内置 NnApiDelegate 构造 delegate"
say "=============================================================="
python - <<'PY' 2>&1 | tee -a "$RESULT"
import tflite_runtime.interpreter as tflite
import traceback

# TFLite 的 NNAPI delegate 在不同版本里暴露方式不同，逐个试
attempts = [
    ("tflite.NnApiDelegate", lambda: tflite.NnApiDelegate()),
    ("tflite.experimental.NnApiDelegate", lambda: tflite.experimental.NnApiDelegate()),
    ("load_delegate('libneuralnetworks.so')",
        lambda: tflite.load_delegate('libneuralnetworks.so')),
]
ok = None
for name, fn in attempts:
    try:
        d = fn()
        print(f"成功: {name}  -> {d!r}")
        ok = d
        break
    except Exception as e:
        print(f"失败: {name}")
        print(f"      {type(e).__name__}: {e}")
print()
if ok is None:
    print("结论: 没有任何可用的 NNAPI delegate 入口")
    print("      → TFLite runtime 这个构建没编入 NNAPI delegate，")
    print("        NPU 这条路在 Termux 内走不通（需换带 delegate 的 App）")
PY

say ""
say "=============================================================="
say " 三、若 delegate 可用，造模型并对比 CPU vs NNAPI"
say "=============================================================="
python - <<'PY' 2>&1 | tee -a "$RESULT"
import numpy as np
import time
import tflite_runtime.interpreter as tflite

def build_model():
    """手工构造一个最小的 TFLite 模型：一个 FULLY_CONNECTED。
       不依赖 tensorflow 包（Termux 没装），直接拼 flatbuffer 太麻烦，
       所以用 TFLite 自带的测试模型路径：tflite_runtime 包内自带示例模型。
       找不到就退回用 add 模型。"""
    import os, glob
    # 先找包内自带的示例模型
    base = os.path.dirname(tflite.__file__)
    cands = glob.glob(os.path.join(base, "**", "*.tflite"), recursive=True)
    if cands:
        return cands[0]
    return None

model_path = build_model()
print("示例模型:", model_path)
if not model_path:
    print("TFLite runtime 包内没有自带 .tflite 模型")
    print("→ 跳过实跑对比。但第二步的 delegate 探测结果已经能回答核心问题。")
    raise SystemExit(0)

def run(interp, label):
    interp.allocate_tensors()
    ind = interp.get_input_details()
    outd = interp.get_output_details()
    for d in ind:
        shape = d['shape']
        dtype = d['dtype']
        if np.issubdtype(dtype, np.floating):
            data = np.random.rand(*shape).astype(dtype)
        else:
            data = np.random.randint(0, 2, size=shape).astype(dtype)
        interp.set_tensor(d['index'], data)
    t0 = time.perf_counter()
    interp.invoke()
    t1 = time.perf_counter()
    out = interp.get_tensor(outd[0]['index'])
    print(f"  {label}: 耗时 {(t1-t0)*1000:.3f} ms   输出形状 {out.shape}   前3值 {out.flatten()[:3]}")
    return t1 - t0

print("--- 纯 CPU ---")
try:
    it_cpu = tflite.Interpreter(model_path=model_path)
    t_cpu = run(it_cpu, "CPU")
except Exception as e:
    print("  CPU 运行失败:", e)
    t_cpu = None

print("--- NNAPI delegate ---")
try:
    d = tflite.NnApiDelegate()
    it_npu = tflite.Interpreter(model_path=model_path, experimental_delegates=[d])
    t_npu = run(it_npu, "NNAPI")
except Exception as e:
    print("  NNAPI 运行失败:", type(e).__name__, e)
    t_npu = None

print()
if t_cpu and t_npu:
    print(f"结果: CPU {t_cpu*1000:.3f} ms  vs  NNAPI {t_npu*1000:.3f} ms")
    print(f"      NNAPI 相对 CPU: {'快' if t_npu < t_cpu else '慢'} {abs(t_npu/t_cpu - 1)*100:.1f}%")
else:
    print("结果: 无法完成对比")
PY

say ""
say "=============================================================="
say " 结论判读"
say "=============================================================="
say " 第二步若能成功构造 NnApiDelegate"
say "     → NPU 有可用入口，第三步的数字就是 CPU vs NPU 的对比"
say " 第二步全部失败"
say "     → TFLite runtime 这个构建不含 NNAPI delegate"
say "       要验证 NPU 只能换一个自带 delegate 的 App（如 LiteRT-LM 的 MTK 版）"
say " 注意：即便 NPU 能跑通，llama.cpp 也用不上它——"
say "       GGUF 模型无法映射到 NNAPI 算子集，这是格式层面的阻断。"
