# termux-npu-probe.sh 说明

## 这是什么

在 Termux（普通应用身份、无 root）里验证天玑 8300 的 **APU 780** 到底能不能摸到。它回答的是「NPU 这条路走不走得通」，而不是「NPU 快不快」——后者要等路走通了才有意义。

## 背景：电脑侧已经查明的事实

```text
/dev/apusys            权限位 crw-rw-rw-，但 shell 身份实测读不出也写不进
                       → 拦它的是 SELinux 域策略，不是文件权限

NNAPI HAL 服务          android.hardware.neuralnetworks-shim-service-mtk 正在跑
binder 上注册了三个      android.hardware.neuralnetworks.IDevice/mtk-dsp_shim
                       android.hardware.neuralnetworks.IDevice/mtk-mdla_shim
                       android.hardware.neuralnetworks.IDevice/mtk-neuron_shim

厂商库齐备               libneuron_runtime.so、libneuron_adapter_mgvi.so、
                       libneuron_platform.so、libapu_mdw.so、
                       libapu_mdw_batch.so、libtflite_mtk.so（6.2 MB）

固件齐备                 /vendor/etc/nn/ot/neuron_detection.mdla3_5
                       /vendor/etc/nn/ot/neuron_tracking.mdla5_0

调优配置                 /vendor/etc/nnapi_powerhal.json
                       内含 MDLA 编译选项 -O3 --gno=SMP --num-mdla 2 --opt-accuracy
```

**这台的局面和华为那台有本质区别**：华为是 vendor 根本没暴露节点与库（"接口没暴露"），这台是节点与库全都在、`/dev/mali0` 与 `/dev/apusys` 权限位都是 `crw-rw-rw-`、NNAPI HAL 正在跑——**接口是开着的**。问题变成了「门开着，但让不让第三方应用进」。

## 三层递进验证

任何一层通了都算有路，但三层通了的实用价值完全不同：

```text
L1  直连内核接口
    dd 读 /dev/apusys 及各个 APU 节点，逐个做「权限位 + 真实 open + 可写」三重判定
    通了 → 理论上可自己写 apusys 驱动调用，但需要 MediaTek 私有 ioctl 定义，实际不可行

L2  直连厂商库
    写一个最小 C 程序 dlopen libneuron_runtime.so / libneuron_adapter_mgvi.so / libapu_mdw.so
    通了 → NPU 软件栈可达，但缺「模型转换 + 会话组装」的完整 API 认知，
          属于「能摸到但没法用」

L3  走标准 API（NNAPI）
    写一个最小 C 程序调用 ANeuralNetworks_getDeviceCount() 枚举加速器设备
    通了 → 唯一有实际意义的路径，可以用 LiteRT / TFLite 跑 NPU 加速模型
```

## L3 的关键约束

**Android 10 起 NNAPI 收紧了应用可见性。** `ANeuralNetworks_getDeviceCount()` 只对以下调用方返回非零：

```text
1. 系统应用
2. 持有 android.permission.NNAPI_ACCESS 签名权限的应用
3. 在设备所有人白名单里的应用，且设备被标记为非受限
```

Termux 是普通第三方应用，三个条件一条都不满足。所以**预期结论是设备数为 0**。

这个结论必须靠跑程序证实，不能靠读文档下结论——所以脚本里确实写了那个 C 程序并编译运行，而不是只打印一段说明。

## 输入

无参数。全部只读，不加载模型、不提交推理任务。

## 输出

```text
身份信息          uid / gid / SELinux 上下文（对比 shell 域的 u:r:shell:s0）

L1 节点判定       每个节点的权限位 + 真实可读 + 可写
APU sysfs         /sys/devices/platform/mdla、sys/class/apusys_drv_apummu 等

L2 库可读性       七个厂商 .so 的大小与可读性
DT_NEEDED         libneuron_runtime.so 还要拉哪些库
dlopen 实验       编译并运行最小 C 程序，打印每个库的加载结果与找到的符号

L3 HAL 状态       init.svc 属性、进程、binder 服务
NNAPI 枚举实验    编译并运行最小 C 程序，打印设备数与各设备名称

结论速查          三层各自通了意味着什么
```

## 编译依赖

脚本里的两个 C 实验需要 `clang`。没有的话先 `pkg install clang`（约 100 MB）。NNAPI 实验直接链接 `/system/lib64/libneuralnetworks.so`，不需要 Android NDK——脚本用手工声明的函数原型绕开了 NDK 头文件依赖。

## 判读结论

```text
L1 不可读 + L2 dlopen 成功 + L3 设备数 0
     → 最可能的组合。软件栈在、框架层准入被拒，
       结论是：想用 NPU 只能改用 LiteRT-LM 这类自带厂商 delegate 的方案，
       且该 delegate 是否受 NNAPI 准入限制需要单独验证

L1 不可读 + L2 dlopen 失败 + L3 设备数 0
     → 三层全断，NPU 完全不可用，与华为那台结论一致

L3 设备数 > 0
     → 出现意外，得重新评估。此时可以看到设备名里有 mtk-mdla / mtk-neuron，
       意味着 MediaTek 的 shim 对普通应用可见，NPU 这条路值得继续投入
```

## 不负责

不判断 NPU 的性能。就算 L3 通了，NPU 在 decode 阶段是否比 CPU 快是另一个问题——已有学术实测（覆盖 llama.cpp / MNN / MLC-LLM 等五个框架）表明 **NPU 在 decode 阶段反而落后于 CPU**，因为 NPU 是静态图执行、需要预先分配固定形状的大窗口，而 decode 是「一次一个 token、上下文持续增长」的小核动态负载。

## 对应文件

- `termux-npu-probe.sh` 本脚本
- `termux-gpu-setup.sh` GPU 侧安装与验证
- `tools/gpu-npu-reach.sh` 电脑侧的同类探测（shell 身份）
