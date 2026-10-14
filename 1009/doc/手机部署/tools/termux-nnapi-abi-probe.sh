#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 用二分法实测 NNAPI 的 OperandType 结构体布局
#
# 问题：
#   手写 ABI 调用 ANeuralNetworksModel_addOperand 返回 4（ANEURALNETWORKS_BAD_DATA）。
#   可能原因：结构体大小或字段顺序与真实 ABI 不一致。
#   Android 的实现在 addOperand 里会校验结构体大小，
#   所以可以靠「试不同布局、看哪个不返回 BAD_DATA」反推出真实定义。
#
# 试的三种布局（都来自公开资料的不同版本描述）：
#   L1  5 字段，无 extraParams
#       { int32 type; uint32 dimCount; uint32* dims; float scale; int32 zeroPoint; }
#   L2  5 字段 + 1 指针（API 30 起新增 extraParams）
#       { ...同 L1; void* extraParams; }
#   L3  6 字段，dimensions 放在最后（早期 ABI 的一种写法）
#
# 判定：
#   rc=0  → 该布局正确
#   rc=4  → 结构体不合法
#
# 用法：
#   bash termux-nnapi-abi-probe.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
T="$TMPDIR/abiprobe"
mkdir -p "$T"

cat > "$T/probe.c" <<'CEOF'
/* 二分法探测 NNAPI OperandType 的真实 ABI 布局。 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <dlfcn.h>

typedef struct ANeuralNetworksModel ANeuralNetworksModel;
typedef int (*fn_create)(ANeuralNetworksModel **);
typedef int (*fn_addOp)(ANeuralNetworksModel *, const void *);

/* ---- 布局 L1：5 字段，无 extraParams ---- */
typedef struct {
    int32_t  type;
    uint32_t dimensionCount;
    const uint32_t *dimensions;
    float    scale;
    int32_t  zeroPoint;
} OT_L1;

/* ---- 布局 L2：L1 + 尾部指针 ---- */
typedef struct {
    int32_t  type;
    uint32_t dimensionCount;
    const uint32_t *dimensions;
    float    scale;
    int32_t  zeroPoint;
    const void *extraParams;
} OT_L2;

/* ---- 布局 L3：dimensions 放最后 ---- */
typedef struct {
    int32_t  type;
    uint32_t dimensionCount;
    float    scale;
    int32_t  zeroPoint;
    const uint32_t *dimensions;
} OT_L3;

/* ---- 布局 L4：L2 再加一个尾部指针（应对更多扩展） ---- */
typedef struct {
    int32_t  type;
    uint32_t dimensionCount;
    const uint32_t *dimensions;
    float    scale;
    int32_t  zeroPoint;
    const void *extraParams;
    const void *extraParams2;
} OT_L4;

int main(void) {
    void *h = dlopen("/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so",
                     RTLD_NOW | RTLD_GLOBAL);
    if (!h) { printf("dlopen 失败: %s\n", dlerror()); return 1; }

    fn_create create = (fn_create)dlsym(h, "ANeuralNetworksModel_create");
    fn_addOp  addOp  = (fn_addOp)dlsym(h, "ANeuralNetworksModel_addOperand");
    if (!create || !addOp) { printf("符号缺失\n"); return 1; }

    uint32_t dims[2] = {1, 4};
    /* FLOAT32 的张量类型常量在不同文档里有 0 与 1 两种说法，两种都试 */
    int32_t typeCands[2] = {0, 1};
    const char *typeNames[2] = {"type=0", "type=1"};

    struct { const char *name; size_t size; } layouts[4] = {
        {"L1 (5字段,无extraParams)", sizeof(OT_L1)},
        {"L2 (6字段,+extraParams) ", sizeof(OT_L2)},
        {"L3 (dims放最后)         ", sizeof(OT_L3)},
        {"L4 (7字段,双指针)       ", sizeof(OT_L4)},
    };

    for (int t = 0; t < 2; t++) {
        printf("=========== 尝试 %s (结构体大小需匹配) ===========\n", typeNames[t]);
        for (int i = 0; i < 4; i++) {
            ANeuralNetworksModel *m = NULL;
            if (create(&m) != 0) { printf("  建模型失败\n"); continue; }

            /* 按每种布局分别填结构体，union 保证内存足够 */
            unsigned char buf[128];
            memset(buf, 0, sizeof(buf));

            if (i == 0) {
                OT_L1 o = {0}; o.type = typeCands[t]; o.dimensionCount = 2;
                o.dimensions = dims; o.scale = 0.0f; o.zeroPoint = 0;
                memcpy(buf, &o, sizeof(o));
            } else if (i == 1) {
                OT_L2 o = {0}; o.type = typeCands[t]; o.dimensionCount = 2;
                o.dimensions = dims; o.scale = 0.0f; o.zeroPoint = 0;
                o.extraParams = NULL;
                memcpy(buf, &o, sizeof(o));
            } else if (i == 2) {
                OT_L3 o = {0}; o.type = typeCands[t]; o.dimensionCount = 2;
                o.dimensions = dims; o.scale = 0.0f; o.zeroPoint = 0;
                memcpy(buf, &o, sizeof(o));
            } else {
                OT_L4 o = {0}; o.type = typeCands[t]; o.dimensionCount = 2;
                o.dimensions = dims; o.scale = 0.0f; o.zeroPoint = 0;
                memcpy(buf, &o, sizeof(o));
            }

            int rc = addOp(m, buf);
            printf("   %s  size=%2zu  -> rc=%d %s\n", layouts[i].name,
                   layouts[i].size, rc, rc == 0 ? " <<< 成功！布局正确" : "");
        }
        printf("\n");
    }

    printf("说明：rc=0 的那一行就是正确的 ABI 布局与类型常量。\n");
    printf("      rc=4 表示 ANEURALNETWORKS_BAD_DATA，即结构体不合法。\n");
    return 0;
}
CEOF

echo "=============================================================="
echo " 编译并运行 ABI 布局探测"
echo "=============================================================="
if clang -o "$T/probe" "$T/probe.c" -ldl 2>&1; then
  "$T/probe" 2>&1
else
  echo "编译失败"
fi
