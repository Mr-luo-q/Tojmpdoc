# gpu-npu-reach.sh 说明

## 这是什么

GPU / NPU **可达性**深探脚本，是 `gpu-npu-probe.sh` 的第二轮。第一轮问「有什么硬件」，这一轮问「我这个身份能不能用」。

这两件事必须分开，因为 Android 上有两道独立且都会否决的门：

```text
第一道  文件权限位     ls -l 能看到的 rwx
第二道  SELinux 域策略  ls -l 看不到，但 open() 会被 avc 拒绝
```

第一轮只能看到第一道。实测证据：`/dev/apusys` 权限位是 `crw-rw-rw-`，照理"人人可写"，但以 `u:r:shell:s0` 身份 `dd` 读一个字节直接失败。**只看权限位会得出完全错误的结论。**

## 输入

无参数。建议在两个不同身份下各跑一次，对比差异：

```bash
adb shell sh /data/local/tmp/gpu-npu-reach.sh              # shell 域 u:r:shell:s0
adb shell run-as com.termux sh ~/gpu-npu-reach.sh          # Termux 的 app 域
```

## 输出

```text
[0] 我是谁                 uid/gid、SELinux 上下文、SELinux 模式
[1] L1 内核接口层          每个算力节点做「权限位 + 真实 open/read + 可写」三重判定
[2] L2 用户态库层          厂商 .so 在哪个分区、能否读、导出了什么符号、依赖链
[3] L3 框架服务层          NNAPI HAL 是否注册、binder 上有没有设备、powerhal 调优配置
[4] 直接加载测试           用 linker 直接加载厂商库，看拒绝发生在哪一层
```

## 三层递进的判断逻辑

```text
L1 内核接口层
    节点能 open      → 理论上可自己写驱动调用（需厂商私有 ioctl 定义，实际不可行）
    节点打不开       → SELinux 域策略挡住，到此为止

L2 用户态库层
    dlopen 成功      → NPU 软件栈可达，但缺「模型转换 + 会话组装」的完整 API 认知
    dlopen 失败      → linker namespace 或 SELinux 拒绝加载 vendor 库

L3 框架服务层
    NNAPI 枚举到设备 → 唯一有实际意义的路径，可用 LiteRT / TFLite 跑 NPU 加速
    NNAPI 枚举为 0   → Android 框架层对第三方应用关闭了 NNAPI
```

L3 是最关键的一层。**Android 10 起 NNAPI 收紧了应用可见性**：`ANeuralNetworks_getDeviceCount()` 只对系统应用、或持有 `android.permission.NNAPI_ACCESS` 签名权限的应用、或在设备白名单里的应用返回非零。Termux 是普通第三方应用，三个条件都不满足。

这解释了一个容易误判的现象：**手机上确实有 NPU、HAL 在跑、binder 服务已注册、厂商库都在，但第三方应用一条都用不上。** 接口没被"藏起来"，是被准入策略挡在门外。

## 实测记录（Redmi K70E，shell 身份 u:r:shell:s0）

```text
/dev/mali0            crw-rw-rw-  可写    ← GPU 这层是敞开的
/dev/apusys           crw-rw-rw-  读写皆失败  ← 权限位好看，SELinux 拦
/dev/apusys_apummu    crw-------  root 独占
/dev/apusys_sapu      crw-------  root 独占
/dev/dri/card0        crw-rw----  system 组

NNAPI binder 上注册了三个设备：
  android.hardware.neuralnetworks.IDevice/mtk-dsp_shim
  android.hardware.neuralnetworks.IDevice/mtk-mdla_shim
  android.hardware.neuralnetworks.IDevice/mtk-neuron_shim
HAL 进程：android.hardware.neuralnetworks-shim-service-mtk（system，pid 1368）

/vendor/etc/nnapi_powerhal.json 里的 MDLA 编译选项：
  -O3 --gno=SMP --num-mdla 2 --opt-accuracy
  cpu_cluster 映射：LITTLE=15  BIG=112  ULTRA=0
```

## 不负责

不跑模型、不提交推理任务、不改系统状态。全部只读。

## 对应文件

- `tools/gpu-npu-reach.sh` 本脚本
- `tools/gpu-npu-probe.sh` 第一轮能力探测
- `tools/probe-gpu-npu.ps1` 电脑侧驱动脚本（跑第一轮）
