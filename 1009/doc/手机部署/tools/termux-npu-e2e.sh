#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · NPU 端到端验证（从「看得见」到「算得出」）
#
# 为什么需要这一步：
#   termux-nnapi-enum2.sh 只证明了 NNAPI 能枚举到 4 个设备，
#   但那不等于能用。真正要跑通的是完整流程：
#       建模型 -> 编译（这一步系统挑加速器）-> 执行 -> 读回结果 -> 校验数值
#   只有算出正确答案，才说明 NPU 这条路是活的。
#
# 测试模型的设计（刻意选最小、最能定位问题的形态）：
#   一个两输入一输出的 ADD，形状 1x4，FLOAT32
#   期望输出 = 输入 a + 输入 b
#   这是 NNAPI 上最容易实现、不依赖量化和复杂算子的图。
#
# 为什么不直接测 LLM：
#   llama.cpp 的 GGUF 模型无法映射到 NNAPI 算子集（且上游已移除 NNAPI 后端）。
#   要用 NPU 跑 LLM，模型必须先转成 TFLite/ONNX 并量化，
#   那是独立的一大步，先确认底层通路可用再谈。
#
# 用法：
#   bash termux-npu-e2e.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
T="$TMPDIR/npue2e"
mkdir -p "$T"

NNLIB="/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so"

cat > "$T/e2e.c" <<'CEOF'
/* NNAPI 端到端最小验证：建 ADD 模型 -> 编译 -> 执行 -> 校验结果。
   手工声明 ABI，避免依赖 NDK 头文件。 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <math.h>

/* ---- NNAPI 常量（取自 NeuralNetworksTypes.h，值固定） ---- */
#define ANEURALNETWORKS_FLOAT32            0
#define ANEURALNETWORKS_TENSOR_FLOAT32     0
#define ANEURALNETWORKS_ADD                0
#define ANEURALNETWORKS_NO_ERROR           0
#define ANEURALNETWORKS_PREFER_FAST_SINGLE_ANSWER 0

/* ---- 不透明类型 ---- */
typedef struct ANeuralNetworksModel ANeuralNetworksModel;
typedef struct ANeuralNetworksCompilation ANeuralNetworksCompilation;
typedef struct ANeuralNetworksExecution ANeuralNetworksExecution;
typedef struct ANeuralNetworksDevice ANeuralNetworksDevice;

/* ---- ABI 结构：字段顺序与 NDK 头一致 ---- */
typedef struct {
    int32_t  type;
    uint32_t dimensionCount;
    const uint32_t *dimensions;
    float    scale;
    int32_t  zeroPoint;
} OperandType;

typedef struct {
    int32_t type;
    uint32_t dimensionCount;
    const uint32_t *dimensions;
} OperandTypeSym;

/* ---- 用 dlsym 取函数，避免链接期对不上符号 ---- */
static void *H;
#define L(sym) dlsym(H, sym)

typedef int (*fn_Model_create)(ANeuralNetworksModel **);
typedef int (*fn_Model_addOperand)(ANeuralNetworksModel *, const void *);
typedef int (*fn_Model_setOperandValue)(ANeuralNetworksModel *, int32_t, const void *, size_t);
typedef int (*fn_Model_addOperation)(ANeuralNetworksModel *, int32_t, uint32_t,
                                     const uint32_t *, uint32_t, const uint32_t *);
typedef int (*fn_Model_finish)(ANeuralNetworksModel *);
typedef int (*fn_Compilation_create)(ANeuralNetworksModel *, ANeuralNetworksCompilation **);
typedef int (*fn_Compilation_setPreference)(ANeuralNetworksCompilation *, int32_t);
typedef int (*fn_Compilation_finish)(ANeuralNetworksCompilation *);
typedef int (*fn_Execution_create)(ANeuralNetworksCompilation *, ANeuralNetworksExecution **);
typedef int (*fn_Execution_setInput)(ANeuralNetworksExecution *, int32_t, const void *,
                                     const void *, size_t);
typedef int (*fn_Execution_setOutput)(ANeuralNetworksExecution *, int32_t, const void *,
                                      void *, size_t);
typedef int (*fn_Execution_startCompute)(ANeuralNetworksExecution *, void *);
typedef int (*fn_Event_wait)(void *);
typedef int (*fn_Event_create)(void **);
typedef int (*fn_getDeviceCount)(uint32_t *);
typedef int (*fn_getDevice)(uint32_t, ANeuralNetworksDevice **);
typedef int (*fn_Device_getName)(const ANeuralNetworksDevice *, const char **);
typedef int (*fn_Compilation_setDevices)(ANeuralNetworksCompilation *, uint32_t,
                                         const ANeuralNetworksDevice *const *);

int main(void) {
    H = dlopen("/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so", RTLD_NOW | RTLD_GLOBAL);
    if (!H) { printf("dlopen 失败: %s\n", dlerror()); return 1; }
    printf("NNAPI 库加载成功\n\n");

    fn_Model_create              Model_create              = (fn_Model_create)L("ANeuralNetworksModel_create");
    fn_Model_addOperand          Model_addOperand          = (fn_Model_addOperand)L("ANeuralNetworksModel_addOperand");
    fn_Model_setOperandValue     Model_setOperandValue     = (fn_Model_setOperandValue)L("ANeuralNetworksModel_setOperandValue");
    fn_Model_addOperation        Model_addOperation        = (fn_Model_addOperation)L("ANeuralNetworksModel_addOperation");
    fn_Model_finish              Model_finish              = (fn_Model_finish)L("ANeuralNetworksModel_finish");
    fn_Compilation_create        Compilation_create        = (fn_Compilation_create)L("ANeuralNetworksCompilation_create");
    fn_Compilation_setPreference Compilation_setPreference = (fn_Compilation_setPreference)L("ANeuralNetworksCompilation_setPreference");
    fn_Compilation_finish        Compilation_finish        = (fn_Compilation_finish)L("ANeuralNetworksCompilation_finish");
    fn_Execution_create          Execution_create          = (fn_Execution_create)L("ANeuralNetworksExecution_create");
    fn_Execution_setInput        Execution_setInput        = (fn_Execution_setInput)L("ANeuralNetworksExecution_setInput");
    fn_Execution_setOutput       Execution_setOutput       = (fn_Execution_setOutput)L("ANeuralNetworksExecution_setOutput");
    fn_Execution_startCompute    Execution_startCompute    = (fn_Execution_startCompute)L("ANeuralNetworksExecution_startCompute");
    fn_Event_create              Event_create              = (fn_Event_create)L("ANeuralNetworksEvent_create");
    fn_Event_wait                Event_wait                = (fn_Event_wait)L("ANeuralNetworksEvent_wait");
    fn_getDeviceCount            getDeviceCount            = (fn_getDeviceCount)L("ANeuralNetworks_getDeviceCount");
    fn_getDevice                 getDevice                 = (fn_getDevice)L("ANeuralNetworks_getDevice");
    fn_Device_getName            Device_getName            = (fn_Device_getName)L("ANeuralNetworksDevice_getName");
    fn_Compilation_setDevices    Compilation_setDevices    = (fn_Compilation_setDevices)L("ANeuralNetworksCompilation_setDevices");

    if (!Model_create || !Model_addOperand || !Compilation_create || !Execution_startCompute) {
        printf("关键符号缺失，无法继续\n"); return 1;
    }

    /* 先枚举设备，把可选的加速器打印出来 */
    uint32_t nd = 0;
    if (getDeviceCount) getDeviceCount(&nd);
    printf("可用加速器设备: %u 个\n", nd);
    ANeuralNetworksDevice *devs[8];
    uint32_t dn = nd > 8 ? 8 : nd;
    for (uint32_t i = 0; i < dn; i++) {
        devs[i] = NULL;
        if (getDevice) getDevice(i, &devs[i]);
        const char *nm = NULL;
        if (devs[i] && Device_getName) Device_getName(devs[i], &nm);
        printf("   [%u] %s\n", i, nm ? nm : "(?)");
    }
    printf("\n");

    /* ---- 建模型：out = a + b，形状 1x4 FLOAT32 ---- */
    uint32_t dims[2] = {1, 4};
    OperandType ot;
    memset(&ot, 0, sizeof(ot));
    ot.type = ANEURALNETWORKS_TENSOR_FLOAT32;
    ot.dimensionCount = 2;
    ot.dimensions = dims;
    ot.scale = 0.0f;
    ot.zeroPoint = 0;

    ANeuralNetworksModel *m = NULL;
    int rc = Model_create(&m);
    printf("Model_create            rc=%d\n", rc);
    rc = Model_addOperand(m, &ot); printf("addOperand(a)           rc=%d\n", rc);
    rc = Model_addOperand(m, &ot); printf("addOperand(b)           rc=%d\n", rc);
    rc = Model_addOperand(m, &ot); printf("addOperand(out)         rc=%d\n", rc);

    float a[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    float b[4] = {10.0f, 20.0f, 30.0f, 40.0f};
    /* 常量输入必须用 setOperandValue 而不是 setInput，
       否则编译期会因为形状不定而被拒 */
    Model_setOperandValue(m, 0, a, sizeof(a));
    Model_setOperandValue(m, 1, b, sizeof(b));

    uint32_t ins[2] = {0, 1};
    uint32_t outs[1] = {2};
    rc = Model_addOperation(m, ANEURALNETWORKS_ADD, 2, ins, 1, outs);
    printf("addOperation(ADD)       rc=%d\n", rc);
    rc = Model_finish(m);
    printf("Model_finish            rc=%d  <-- 0 表示图合法\n", rc);
    if (rc) { printf("模型不合法，终止\n"); return 1; }

    /* ---- 编译 ---- */
    ANeuralNetworksCompilation *c = NULL;
    rc = Compilation_create(m, &c);
    printf("Compilation_create      rc=%d\n", rc);
    if (Compilation_setPreference)
        Compilation_setPreference(c, ANEURALNETWORKS_PREFER_FAST_SINGLE_ANSWER);

    /* 先不指定设备，让系统自动挑；若失败再逐个指定 */
    rc = Compilation_finish(c);
    printf("Compilation_finish      rc=%d  <-- 0 表示有加速器接单\n", rc);

    if (rc != 0 && Compilation_setDevices) {
        printf("\n自动分配失败，改为逐个指定设备重试：\n");
        for (uint32_t i = 0; i < dn; i++) {
            if (!devs[i]) continue;
            const char *nm = NULL; Device_getName(devs[i], &nm);
            ANeuralNetworksCompilation *c2 = NULL;
            if (Compilation_create(m, &c2) != 0) continue;
            int r2 = Compilation_setDevices(c2, 1, (const ANeuralNetworksDevice *const *)&devs[i]);
            if (r2 == 0) r2 = Compilation_finish(c2);
            printf("   指定 %-20s -> rc=%d %s\n", nm ? nm : "?", r2,
                   r2 == 0 ? "(成功)" : "");
            if (r2 == 0) { c = c2; rc = 0; break; }
        }
    }
    if (rc) { printf("\n没有任何设备能编译这个模型\n"); return 1; }

    /* ---- 执行 ---- */
    ANeuralNetworksExecution *e = NULL;
    rc = Execution_create(c, &e);
    printf("\nExecution_create        rc=%d\n", rc);
    if (rc) return 1;

    float out[4] = {0, 0, 0, 0};
    /* 常量已写进模型，这里把两个输入都标为常量后无需再 setInput；
       为演示完整流程，仍显式设一次输出缓冲 */
    rc = Execution_setOutput(e, 2, NULL, out, sizeof(out));
    printf("Execution_setOutput     rc=%d\n", rc);

    void *ev = NULL;
    rc = Execution_startCompute(e, &ev);
    printf("Execution_startCompute  rc=%d\n", rc);
    if (rc) return 1;

    if (ev && Event_wait) {
        int wr = Event_wait(ev);
        printf("Event_wait              rc=%d\n", wr);
    }

    /* ---- 校验 ---- */
    float exp[4] = {11.0f, 22.0f, 33.0f, 44.0f};
    printf("\n结果校验:\n");
    printf("   期望  11 22 33 44\n");
    printf("   实际  %.0f %.0f %.0f %.0f\n", out[0], out[1], out[2], out[3]);
    int ok = 1;
    for (int i = 0; i < 4; i++) if (fabsf(out[i] - exp[i]) > 0.001f) ok = 0;
    if (ok) printf("\n>>> NPU/NNAPI 端到端通路【跑通】，数值正确\n");
    else    printf("\n>>> 流程走完了但数值不对，需要排查\n");
    return ok ? 0 : 2;
}
CEOF

echo "=============================================================="
echo " 编译并运行 NPU 端到端测试"
echo "=============================================================="
if clang -o "$T/e2e" "$T/e2e.c" -ldl -lm 2>&1; then
  echo "编译成功（用 dlopen 取符号，不依赖链接期解析）"
  echo
  "$T/e2e" 2>&1
else
  echo "编译失败"
fi

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 Compilation_finish 返回 0 且数值校验通过
     → NPU 通路是活的。下一步的意义在于：
       要跑 LLM，需要把模型转成 TFLite/ONNX 并量化，
       再用 NNAPI delegate 执行。llama.cpp 的 GGUF 无法走这条路。

 Compilation_finish 非 0（例如 1=BAD_DATA, 2=BAD_STATE, 3=INVALID_ARGUMENT）
     → 枚举得到设备但实际不可用，NPU 在 Termux 内到此为止。

 若指定 mtk-mdla_shim / mtk-neuron_shim 能编译而自动分配失败
     → 说明必须显式绑设备，这对后续写实际推理程序是关键信息。
EOF
