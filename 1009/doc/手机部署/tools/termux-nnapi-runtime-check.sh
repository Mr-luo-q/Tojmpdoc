#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 用现成运行时验证 NNAPI 能否真正跑推理
#
# 已确认（termux-nnapi-enum2.sh）：
#   Termux 能 dlopen APEX 里的 libneuralnetworks.so，
#   ANeuralNetworks_getDeviceCount 返回 4：
#       mtk-dsp_shim / mtk-mdla_shim / mtk-neuron_shim / nnapi-reference
#
# 本脚本要往前走一步：确认「能枚举」之后，「能真的把算子扔给 NPU」。
# 手段是检查两个现成运行时的 NNAPI 支持：
#   onnxruntime        —— 看它的 NNAPI Execution Provider 是否编译进来
#   tflite-runtime     —— 看它是否暴露 NNAPI delegate
#
# 注：llama.cpp 不在备选里。它的 GGUF/GGML 图无法映射到 NNAPI 算子集，
#     而且 llama.cpp 上游已移除 NNAPI 后端。NPU 这条路必须换模型格式。
#
# 用法：
#   bash termux-nnapi-runtime-check.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

echo "=============================================================="
echo " 第 1 步 · 安装 ONNX Runtime 与 TFLite Runtime"
echo "=============================================================="
info "pkg install onnxruntime python-tflite-runtime python-numpy"
pkg install -y onnxruntime python-tflite-runtime python-numpy 2>&1 | tail -12

echo
echo "=============================================================="
echo " 第 2 步 · ONNX Runtime 的 NNAPI Execution Provider"
echo "=============================================================="
python - <<'PY' 2>&1
try:
    import onnxruntime as ort
    print("onnxruntime 版本:", ort.__version__)
    provs = ort.get_available_providers()
    print("可用 Execution Provider:")
    for p in provs:
        print("   -", p)
    # NNAPI 是 Android 专用 EP，名字固定为 NnapiExecutionProvider
    print()
    if "NnapiExecutionProvider" in provs:
        print("判据: ONNX Runtime 带 NNAPI EP -> 可以把 ONNX 模型丢给 mtk-mdla/mtk-neuron")
    else:
        print("判据: 没有 NNAPI EP，这个构建用不上 NPU")
        print("      （Termux 的构建可能只开了 CPU EP）")
except Exception as e:
    print("导入 onnxruntime 失败:", e)
PY

echo
echo "=============================================================="
echo " 第 3 步 · TFLite Runtime 的 NNAPI delegate"
echo "=============================================================="
python - <<'PY' 2>&1
try:
    import tflite_runtime.interpreter as tflite
    print("tflite_runtime 导入成功")
    # 有新老两种命名，都要试
    names = [n for n in dir(tflite) if "NNAPI" in n.upper() or "Delegate" in n]
    print("与 delegate 相关的符号:", names if names else "(无)")
    print()
    print("尝试构造 NNAPI delegate:")
    ok = False
    for ctor in ("load_delegate",):
        f = getattr(tflite, ctor, None)
        if not f:
            continue
        for lib in ("libneuralnetworks.so",
                    "/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so"):
            try:
                d = f(lib)
                print(f"   {ctor}('{lib}') -> 成功: {d}")
                ok = True
                break
            except Exception as e:
                print(f"   {ctor}('{lib}') -> 失败: {type(e).__name__}: {e}")
    if not ok:
        print("判据: 没有可用的 NNAPI delegate 加载路径")
except Exception as e:
    print("导入 tflite_runtime 失败:", e)
    print("（Termux 的包名可能是 tflite_runtime，若失败说明该构建不含 Python 绑定）")
PY

echo
echo "=============================================================="
echo " 第 4 步 · 直接用 C API 走一遍完整 NNAPI 流程（不依赖任何 Python 包）"
echo "=============================================================="
# 这是最硬的证据：用 NNAPI 的 C API 建一个最小模型（一个 ADD 算子），
# 编译它，看是否能在不指定设备（让系统自动选）时成功走到编译阶段。
# 若编译阶段报「没有可用设备」，说明枚举到的设备其实不可用。
T="$TMPDIR/nnapi3"
mkdir -p "$T"
cat > "$T/minimal.c" <<'EOF'
/* 最小 NNAPI 全流程：建模型 -> 编译（这一步会挑设备）-> 看结果。
   编译成功说明枚举到的加速器确实可以被使用，不只是"看得见"。 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef struct ANeuralNetworksModel ANeuralNetworksModel;
typedef struct ANeuralNetworksCompilation ANeuralNetworksCompilation;
typedef struct ANeuralNetworksDevice ANeuralNetworksDevice;

extern int ANeuralNetworksModel_create(ANeuralNetworksModel **model);
extern int ANeuralNetworksModel_addOperand(ANeuralNetworksModel *model, const void *type);
extern int ANeuralNetworksModel_setOperandValue(ANeuralNetworksModel *model, int32_t index,
                                                const void *buffer, size_t length);
extern int ANeuralNetworksModel_addOperation(ANeuralNetworksModel *model, int32_t type,
                                             uint32_t inputCount, const uint32_t *inputs,
                                             uint32_t outputCount, const uint32_t *outputs);
extern int ANeuralNetworksModel_finish(ANeuralNetworksModel *model);
extern int ANeuralNetworksCompilation_create(ANeuralNetworksModel *model,
                                             ANeuralNetworksCompilation **compilation);
extern int ANeuralNetworksCompilation_finish(ANeuralNetworksCompilation *compilation);
extern int ANeuralNetworks_getDeviceCount(uint32_t *numDevices);
extern int ANeuralNetworks_getDevice(uint32_t devIndex, ANeuralNetworksDevice **device);
extern int ANeuralNetworksDevice_getName(const ANeuralNetworksDevice *device, const char **name);

/* NNAPI 的 ANeuralNetworksOperandType 结构（ABI 固定，这里手写布局） */
typedef struct {
    int32_t type;
    uint32_t dimensionCount;
    const uint32_t *dimensions;
    float scale;
    int32_t zeroPoint;
} OperandType;

#define ANEURALNETWORKS_TENSOR_FLOAT32 0
#define ANEURALNETWORKS_ADD 0

int main(void) {
    uint32_t n = 0;
    ANeuralNetworks_getDeviceCount(&n);
    printf("枚举到设备数: %u\n", n);

    /* 建一个 1x4 的 FLOAT32 张量类型，两个输入一个输出，做一个 ADD */
    uint32_t dims[2] = {1, 4};
    OperandType t = {0};
    t.type = ANEURALNETWORKS_TENSOR_FLOAT32;
    t.dimensionCount = 2;
    t.dimensions = dims;
    t.scale = 0.0f;
    t.zeroPoint = 0;

    ANeuralNetworksModel *m = NULL;
    int rc = ANeuralNetworksModel_create(&m);
    printf("Model_create rc=%d\n", rc);
    if (rc) return 1;

    ANeuralNetworksModel_addOperand(m, &t);   /* 0: 输入 a */
    ANeuralNetworksModel_addOperand(m, &t);   /* 1: 输入 b */
    ANeuralNetworksModel_addOperand(m, &t);   /* 2: 输出   */

    float data[4] = {1,2,3,4};
    ANeuralNetworksModel_setOperandValue(m, 0, data, sizeof(data));
    ANeuralNetworksModel_setOperandValue(m, 1, data, sizeof(data));

    uint32_t in[2] = {0, 1};
    uint32_t out[1] = {2};
    rc = ANeuralNetworksModel_addOperation(m, ANEURALNETWORKS_ADD, 2, in, 1, out);
    printf("addOperation(ADD) rc=%d\n", rc);

    rc = ANeuralNetworksModel_finish(m);
    printf("Model_finish rc=%d\n", rc);
    if (rc) return 1;

    /* 关键一步：编译。系统会在这一阶段决定用哪个加速器 */
    ANeuralNetworksCompilation *c = NULL;
    rc = ANeuralNetworksCompilation_create(m, &c);
    printf("Compilation_create rc=%d\n", rc);
    if (rc) return 1;

    rc = ANeuralNetworksCompilation_finish(c);
    printf("Compilation_finish rc=%d  <-- 0 表示加速器真的接单了\n", rc);
    return 0;
}
EOF

if clang -o "$T/minimal" "$T/minimal.c" \
     /apex/com.android.neuralnetworks/lib64/libneuralnetworks.so 2>&1; then
  info "编译成功，运行"
  "$T/minimal" 2>&1
else
  echo "链接失败，改用 dlopen 方式（部分符号在 APEX 里不导出）"
fi

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
cat <<'EOF'
 判读：

 ONNX Runtime 有 NnapiExecutionProvider，或 TFLite 能 load_delegate NNAPI
     → NPU 有现成的落地工具，下一步只需准备一个转换好的模型
       （int8 量化的 ONNX 或 TFLite），就能实测 NPU 推理速度

 两者都没有，但第 4 步的 C API 流程能跑到 Compilation_finish 返回 0
     → NPU 在系统层面可用，只是 Termux 的现成包没开这个后端，
       需要自己写 NNAPI 调用代码或找带 NNAPI 的构建

 全都失败
     → 枚举得到设备但无法实际使用，NPU 到此为止
EOF
