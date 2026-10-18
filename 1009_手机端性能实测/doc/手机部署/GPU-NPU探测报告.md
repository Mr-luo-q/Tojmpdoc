# GPU / NPU 实机探测报告 · Redmi K70E

探测日期：2026-10-09
设备：Redmi K70E（`2311DRK48C`，代号 `duchamp`）
SoC：MediaTek **MT6897** = 天玑 8300-Ultra（4nm）
GPU：Arm **Mali-G615**（驱动 `mali_kbase_mt6897_r44`）
NPU：MediaTek **APU 780**（含 MDLA / MVPU / DSP 三类加速单元）
系统：Android 14（SDK 36），内核 6.1.138-android14-11，HyperOS，SELinux Enforcing
环境：Termux v0.118.3，无 root，普通第三方应用身份

## 一、结论速览

```text
             硬件是否存在   权限位是否放开   实际能否用      卡在哪一层
──────────────────────────────────────────────────────────────────────────────
GPU          ✅ 存在        ✅ 开放          ❌ 不可用       linker namespace
NPU          ✅ 存在        ✅ 开放          ⚠️ 可枚举       NNAPI 能用，
                                                               但 llama.cpp 用不上
CPU          ✅ 存在        —                ✅ 可用         唯一可直接使用的后端
```

三条结论的置信度：**GPU 与 CPU 两条是实测确定的；NPU 的「可枚举」是实测确定的，「能否真正执行推理」未验证完**（原因见第五节）。

## 二、这台机器与上次那台华为的本质区别

上次华为 Pura 70 Pro+ 的结论是「接口没暴露」。这次实测下来，**这台不是没暴露，而是暴露了但不给第三方应用**。三处对比：

```text
                          华为 Pura 70（上次）       红米 K70E（本次）
──────────────────────────────────────────────────────────────────────────
GPU 设备节点               root 独占，普通应用看不到   /dev/mali0 crw-rw-rw-，可写
Vulkan 计算权限手册        无                          有（compute-0 + version-1_3）
Vulkan HAL                 无可用构建                  /vendor/lib64/hw/vulkan.mali.so
GPU 官方 Android 构建      不存在                      Termux 有预编译 Vulkan 后端包
NPU HAL 服务               未提及                      neuralnetworks-shim-service-mtk 在跑
NPU 厂商库                 不可达                      libneuron_runtime.so 等一整套齐备
NPU 加速器可枚举           否                          是，4 个（3 个是联发科的）
```

所以上次的「GPU/NPU 都放弃」在这个平台上有两条需要修正：**GPU 换成了 Termux 官方预编译 Vulkan 后端（不用自己编译），NPU 则意外地能通过 NNAPI 枚举到。**

## 三、GPU：卡在 linker namespace，不是权限也不是驱动

### 3.1 硬件与驱动层面完全正常

```text
/dev/mali0                                    crw-rw-rw-  system graphics
/dev/dri/card0                                crw-rw----  system system
/sys/class/devfreq/13000000.mali              GPU 频率接口
ro.hardware.vulkan = mali                     Vulkan 走后端是 Mali 驱动
/vendor/lib64/hw/vulkan.mali.so               21 字节，符号链接到 mt6897/vulkan.mali.so
/vendor/lib64/egl/mt6897/libGLES_mali.so      46,384,136 字节
/vendor/lib64/libOpenCL.so                    136,624 字节
/vendor/etc/permissions/android.hardware.vulkan.compute-0.prebuilt.xml
/vendor/etc/permissions/android.hardware.vulkan.version-1_3.prebuilt.xml
```

`egl.cfg` 里的软链接结构说明驱动按 SoC 代号分目录：`libGLES_mali.so -> mt6897/libGLES_mali.so`，同目录下还预置了 `mt6985`、`mt6989` 的驱动，说明这是联发科的多机型通用 vendor 分区。

### 3.2 真正拦截它的是 linker namespace

Termux 进程每次尝试读 vendor 库，都会打出这句警告：

```text
WARNING: linker: library "/vendor/lib64/hw/vulkan.mali.so"
  ("/vendor/lib64/hw/mt6897/vulkan.mali.so")
  needed or dlopened by "..." is not accessible for the namespace:
  [name="(default)",
   default_library_paths="/system/lib64:/system_ext/lib64",
   permitted_paths="/system/lib64/drm:/system/lib64/extractors:/system/lib64/hw:
                    /system_ext/lib64:/system/framework:/system/app:/system/priv-app:
                    /vendor/framework:/vendor/app:/vendor/priv-app:
                    /system/vendor/framework:/system/vendor/app:/system/vendor/priv-app:
                    /odm/framework:/odm/app:/odm/priv-app:/oem/app:
                    /product/framework:/product/app:/product/priv-app:
                    /data:/mnt/expand:
                    /apex/com.android.runtime/lib64/bionic:/system/lib64/bootstrap"]
```

**把 `permitted_paths` 逐条看一遍就会发现问题：里面只有 `/vendor/framework`、`/vendor/app`、`/vendor/priv-app`，没有 `/vendor/lib64`。** 这是 AOSP 的标准配置——第三方应用只能读 vendor 分区的 app 类目录，不能读 vendor 的库目录。

这个警告由**系统 loader 自己发出**（注意它报的是 `libvulkan.so.1.4.365` 这个 Termux 库在尝试加载 Mali），说明连 Android 平台的 Vulkan loader 都受同一个 namespace 约束。

### 3.3 一个我犯过并纠正的错误

我一度怀疑是 `adb shell run-as` 造成的假象，理由是「`run-as` 只切 UID 不切 namespace，而真正用图标启动的 App 跑在 classloader-namespace 里，那个 namespace 应该包含 `/vendor/lib64`」。

**这个假设被实测否掉了。** 用 `input text` 把脚本注入 Termux 终端，在真正的 App 进程内复测：

```text
App 进程内 · /proc/self/maps 里的 linker
    /apex/com.android.runtime/bin/linker64      与 run-as 下同一个

App 进程内 · dlopen /vendor/lib64/hw/vulkan.mali.so    被拒
App 进程内 · namespace 仍然是 name="(default)"
App 进程内 · permitted_paths 仍然是同一串，无 /vendor/lib64
```

Termux 这个 App 的 `targetSdk` 与实际 namespace 配置使它落在 `(default)` namespace 里，**与用哪种方式启动无关**。所以「Termux 拿不到 vendor 库」是成立的结论。

### 3.4 Vulkan 枚举到的是软件光栅化器

```text
vkCreateInstance -> 0 (成功)
物理设备数量 -> 1
设备[0] 名称=llvmpipe (LLVM 21.1.8, 128 bits)
        API=1.4.354  驱动版本=0x06802004  类型=4
```

`llvmpipe` 是 Mesa 的 **CPU 软件 Vulkan 实现**。原因在库的形态差异：

```text
/system/lib64/libvulkan.so              269,600 字节   SONAME=libvulkan.so
    依赖 libvndksupport / libhardware / libui / libSurfaceFlingerProp /
         android.hardware.graphics.common@1.0.so 等 27 个库
    → Android 平台 loader，通过 hw_get_module("vulkan") 加载 Mali HAL

Termux usr/lib/libvulkan.so.1.4.365     677,544 字节   SONAME=libvulkan.so.1
    只依赖 libdl / libc
    → 桌面 Linux loader，按 ICD json 找驱动
    → 在 Android 上只找得到自带的 lvp_icd.aarch64.json，即 llvmpipe
```

两者哈希不同、SOAME 不同，是两个独立实现。用绝对路径链系统 loader 也无效——bionic 的链接器在 `DT_NEEDED` 里只记 SONAME（不保留路径），运行时仍被 `DT_RUNPATH` 里的 Termux 目录抢先解析。

### 3.5 有意义的一条：Termux 官方有现成的 Vulkan 后端包

这是本次最省事的发现。Termux 仓库（`packages.termux.dev`）里：

```text
llama-cpp                       0.6.0
llama-cpp-backend-vulkan        0.6.0    28,549,464 字节
llama-cpp-backend-opencl        0.6.0     3,008 KB
ollama                          0.35.1
ollama-backend-vulkan           0.35.1
vulkan-tools                    1.4.365  提供 vulkaninfo
vulkan-loader-android           30
clinfo                          3.1.26
shaderc / glslang / spirv-tools           着色器工具链
```

`llama-cpp-backend-vulkan` 已实测装成功，`libggml-vulkan.so` 就在 `usr/lib/` 下。但因为它链接的是 Termux 那个只看 Mesa ICD 的 loader，**装上也只会落到 llvmpipe**。所以这个包在别的机型（能拿到 Mali ICD 的）上很有价值，在这台上不够。

### 3.6 GPU 的结论

**补充：还试过一条「复制驱动进 /data」的路，取得了部分进展但最终卡在 MediaTek 的依赖复杂度上。**

思路是：namespace 的拦截按**路径前缀**判断，而 `/data` 在 `permitted_paths` 里，所以把 Mali 驱动复制进 Termux 自己的 `usr/lib/` 就能绕过。这个思路被实测部分验证了：

```text
第 1 次尝试  复制到 usr/lib/，dlopen 报
                 dlopen failed: library "libGLES_mali.so" not found:
                 needed by .../usr/lib/vulkan.mali.so in namespace (default)
             注意报错性质变了——从 not accessible for the namespace
             变成了 not found。说明 namespace 那道门确实被绕过了，
             剩下的是目录布局问题。

第 2 次尝试  查到驱动有 RUNPATH=$ORIGIN/../egl，靠它定位 libGLES_mali.so
             （驱动原本在 /vendor/lib64/hw/mt6897/，
               $ORIGIN/../egl 正好是 /vendor/lib64/egl/）
             于是把 libGLES_mali.so 放到与 usr/lib/ 平级的 usr/egl/
             这一层修好了，报错推进到下一个依赖

第 3 次尝试  缺 libged.so（MediaTek 的 GPU 能耗管理库）
             从 /vendor/lib64/libged.so 复制进 usr/lib/，
             但 loader 仍然报同一个错，不再推进
```

**结论：Mali 驱动（10 KB）与 libGLES_mali.so（46 MB）本身能复制成功、`$ORIGIN` 布局也能修正，但依赖链继续深入到 MediaTek 的私有库群，且出现「库明明在搜索路径里却仍报 not found」的循环。**

继续补依赖的风险在于：要从 vendor 分区复制越来越多基础库变体（vendor 版 libc++ / libm 等）进 Termux，可能引入与 Termux 自身运行库冲突的问题，且这类问题很难定位。**这不是设计方案，是在与厂商私有驱动栈搏斗。**

另一个值得记的正面信息：Termux 官方仓库有个 open issue（[termux-packages#30264](https://github.com/termux/termux-packages/issues/30264)），报告人是天玑 9300（Mali-G720）用户，他实测 `vulkan-loader-android` **能正确枚举出 Mali-G720**。他撞到的是另一个问题——`vulkan-loader-android` 把 Termux 的 `libvulkan.so` 符号链接到 `/system/lib64/libvulkan.so`，而 Android 15 起 `libunwindstack.so` 需要系统 liblzma 的 `Xzs_Construct` 符号，Termux 的 liblzma 没有。他的 workaround 是 `LD_PRELOAD=/system/lib64/liblzma.so`。本机是 Android 14，不受该问题影响。

**这条外部证据说明「Termux + Mali」这条路在别的机型上是通的**，本机的障碍是 MediaTek 这套驱动的依赖复杂度，而非 Android 或 Termux 的普遍限制。

### 3.7 GPU 三条路的取舍对比

```text
路子                        已验证的部分              没验证的部分          判断
──────────────────────────────────────────────────────────────────────────────────
复制驱动进 /data            绕过 namespace 成功、       依赖链能否补齐        不推荐
（本次试的）                $ORIGIN 布局可修           复制基础库有无副作用  风险高

Android NDK 交叉编译        未开始                     全部                  推荐
                           Mali 驱动确认完好、        需要约 1 GB NDK
                           Vulkan 1.3 + compute 齐全  与一次完整编译

专用推理 App                未开始                     是否支持 Mali-G615    可评估
（MLC-LLM / MNN 等）       这类 App 跑在正确 namespace  模型格式是否要转换    见下条
```

### 3.8 GPU 的最终结论

```text
能确定的             Mali 驱动完好、Vulkan 1.3 + compute 能力齐备、
                    /dev/mali0 对第三方应用可写、$ORIGIN 布局可修正、
                    复制进 /data 能绕过 namespace
不能确定的           说 Mali 在 Termux 里绝对不可用
唯一稳妥路径         用 Android NDK 交叉编译 → 产出原生 Android 可执行文件
                    或 APK → 运行在正确的 namespace 里
代价                 需要下载 Android NDK（约 1 GB），并重新编译
                    llama.cpp 的 Vulkan 后端
预期收益             prefill 会明显变快；decode 未必——
                    1.5B Q4_K_M 只有 1.1 GB，decode 是纯访存受限，
                    GPU 的显存带宽优势体现不出来
```

## 四、NPU：标准 API 路径可用，但与 llama.cpp 无关

### 4.1 硬件与软件栈完整

```text
/dev/apusys              crw-rw-rw-  system camera
/dev/apuext              crw-r--r--  root root
/dev/apusys_sapu         crw-------  root root
/dev/apusys_apummu       crw-------  root root

HAL 进程                  android.hardware.neuralnetworks-shim-service-mtk（system）
init.svc                  neuralnetworks_hal_service_shim_mtk = running

binder 上注册的三个 IDevice
    android.hardware.neuralnetworks.IDevice/mtk-dsp_shim
    android.hardware.neuralnetworks.IDevice/mtk-mdla_shim
    android.hardware.neuralnetworks.IDevice/mtk-neuron_shim

内核模块                  apusys / apu_top / mdla / sapu / mtk_scp_ultra /
                         mtk_scpsys_mt6897 / adsp / connscp
rpmsg 通道（20 余条）      mdla-tx / mdla-rx / mvpu-tx / mvpu-rx /
                         apu-mdw / apu-edma / apu-apummu / apu-ipi-ut 等
dma_heap                 mtk_sapu_engine_shm_region / mtk_sapu_data_shm_region

厂商库                    libneuron_runtime.so、libneuron_runtime.7.so、
                         libneuron_adapter_mgvi.so、libneuron_platform.so、
                         libneuron_wrapper.so、libapu_mdw.so、
                         libapu_mdw_batch.so、libapudcutils.so、
                         libmdla_ut.so、libtflite_mtk.so（6,262,832 字节）、
                         libneuralnetworks_sl_driver_mtk_prebuilt.so

固件                      /vendor/etc/nn/ot/neuron_detection.mdla3_5
                         /vendor/etc/nn/ot/neuron_detection.mdla5_0
                         /vendor/etc/nn/ot/neuron_tracking.mdla5_1.cache

调优配置                  /vendor/etc/nnapi_powerhal.json
                         MDLA 编译选项：-O3 --gno=SMP --num-mdla 2 --opt-accuracy
                         CPU 簇映射：LITTLE=15  BIG=112  ULTRA=0
```

### 4.2 NNAPI 能枚举到 4 个加速器

这是本次第二个意外发现。**我在脚本注释里预判「Android 10 起 NNAPI 对第三方应用关闭，设备数应为 0」，实测证伪：**

```text
dlopen /apex/com.android.neuralnetworks/lib64/libneuralnetworks.so   成功
ANeuralNetworks_getDeviceCount -> rc=0   设备数=4

  [0] mtk-dsp_shim       version=7.2.4              type=4
  [1] mtk-mdla_shim      version=7.2.4              type=4
  [2] mtk-neuron_shim    version=7.2.4              type=4
  [3] nnapi-reference    version=OS3.0.304.0.WNLCNXM type=2
```

原因也清楚了：MediaTek 把 NPU 做成了 **HAL 服务 + APEX 模块**，走 binder 到 `IDevice`，不受我预判的那条应用白名单限制。而且路径也值得记一笔——`libneuralnetworks.so` 不在 `/system/lib64`，在 APEX 挂载点：

```text
/apex                                 drwxr-xr-x   可访问
/apex/com.android.neuralnetworks      drwxr-xr-x   可访问
/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so   4,955,424 字节  可读
```

来源是 `/system/apex/com.android.neuralnetworks.capex`。我前两次找错位置（先试 `/system/lib64`，再试 `/apex/` 顶层），逐层探测后才定位到。

### 4.3 vendor 库与 APU 节点仍然不可达

```text
/vendor/lib64/libneuron_runtime.so     被拒（linker namespace）
/vendor/lib64/libapu_mdw.so            被拒
/vendor/lib64/hw/vulkan.mali.so        被拒
/dev/apusys                            不可见
/sys/devices/platform/mdla             Permission denied
```

**但 NNAPI 这条路不需要它们**——走 binder 到 HAL 进程，由 HAL 代理访问硬件。所以「直连不可达」与「API 可达」可以同时成立。

### 4.4 与 llama.cpp 的结构性矛盾

这是最需要说清楚的一点：

```text
llama.cpp 用不了 NNAPI，有两层原因

第一层  格式层面
        NNAPI 吃的是「NNAPI 算子图」——由 TFLite / ONNX 转换而来，
        或手工用 ANeuralNetworksModel_addOperation 搭出来。
        GGUF 里的 GGML 图（自定义量化、RoPE 变体、GQA 等）
        没有到 NNAPI 算子集的映射路径。

第二层  框架层面
        llama.cpp 上游已移除 NNAPI 后端，官方预编译包里
        Android arm64 只有 CPU 和 snapdragon（Adreno+Hexagon）两种，
        没有任何 NNAPI / 通用 GPU 资产。

结论    NPU 要跑 LLM，必须换模型格式与推理框架，
        走 LiteRT（原 TFLite）或 LiteRT-LM 的 MediaTek NPU delegate。
        这是独立的一套工程，与 llama.cpp 不共享代码路径。
```

### 4.5 未验证完的部分（如实说明）

为验证「不只可枚举，还能真算」，写了端到端测试（建 ADD 模型 → 编译 → 执行 → 校验数值）。程序能加载库、能枚举设备，但**手工声明的 ABI 结构没能通过参数校验**：

```text
Model_create            rc=0
addOperand(a)           rc=4     ← ANEURALNETWORKS_BAD_DATA
```

用二分法试了四种结构体布局（5 字段 / 6 字段带 extraParams / dims 放最后 / 7 字段双指针），尺寸 24/32/24/40 字节，`type` 常量也试了 0 和 1 两种，**全部返回 4**。说明卡在更前面的参数校验，不是结构体大小问题。

要修得靠三个手段之一，本次都没走通：装 Android NDK 拿到真实的 `NeuralNetworksTypes.h`（约 1 GB 下载，性价比低）；找到 AOSP 原始头文件（多次网络抓取均失败）；或者从 `libneuralnetworks.so` 反汇编校验逻辑。

**所以「NPU 能真正执行推理」这一点，本次没有证实，也没有证伪。** 但即便证实了也不影响主结论——llama.cpp 走不了这条路。

## 五、CPU：完好，是当前唯一可直接使用的后端

```text
内核            Linux 6.1.138-android14-11-g6ab8c9a86a33
ABI             arm64-v8a
逻辑核数        8
支持的特性       fp asimd aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid
                asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512
                sve sve2 sveaes svepmull svebitperm svesha3 svesm4 svei8mm
                svebf16 i8mm bf16 (以及 dit uscat ilrcpc flagm sb paca pacg
                dcpodp frint bti)

各核最大频率     cpu0-3   2,200,000 Hz
                cpu4-6   3,200,000 Hz
                cpu7     3,350,000 Hz

核心拓扑         cpu0 core_id=0   cpu1 core_id=1   cpu2 core_id=2   cpu3 core_id=3
                cpu4 core_id=4   cpu5 core_id=5   cpu6 core_id=6   cpu7 core_id=7
```

`i8mm` + `bf16` + `sve2` 说明量化矩阵乘能吃满现代指令加速，这比上次那台华为（`i8mm` `bf16` `sve`，无 `sve2`）的指令集更全。

## 六、本次踩到并解决的环境问题

```text
问题 1  HyperOS 的 INSTALL_FAILED_USER_RESTRICTED
        现象  adb install 被拒，报 Install canceled by user
        原因  国行 HyperOS（ro.miui.build.region=cn）的防篡改策略，
              adb 侧改不了。相关设置项（verifier_verify_adb_installs 等）
              写需要 WRITE_SECURE_SETTINGS，shell 身份拿不到
        解法  开发者选项 → 打开「USB 安装」。该开关在无 SIM 卡时点不开
              （国行防盗装要求），插卡后即可打开
        附带  adb install -g 也会被拒（INSTALL_GRANT_RUNTIME_PERMISSIONS 受限）

问题 2  USB 调试开关开了但 adb 看不到设备
        现象  Windows 只枚举到 VID_2717&PID_FF40（MTP），无 ADB 接口
        判据  小米的 MTP PID 是 FF40，ADB PID 是 FF48。
              出现 FF48 才算真正打开
        解法  开发者选项里「USB 调试」需要重新开关一次，
              插拔线后才会重新协商 USB 描述符

问题 3  run-as 不带 PATH 与环境变量
        现象  run-as com.termux bash 报 exec failed: Permission denied
        原因  bash 会走 PATH 查找，而 run-as 不设置 PATH
        解法  用绝对路径 /data/data/com.termux/files/usr/bin/bash，
              并把环境设置固化成 tools/termux-run.sh 包装器

问题 4  libc++ 版本不匹配
        现象  CANNOT LINK EXECUTABLE: cannot locate symbol
              "_ZNSt6__ndk113__hash_memoryEPKvm"
        说明  该符号是 std::__ndk1::__hash_memory(void const*, unsigned long)，
              与上次华为「在手机上编译失败」撞到的是同一个符号，
              但性质完全不同：
                  华为那次  源码编译 vs 工具链 libc++ ABI 不匹配，无解
                  本次      预编译包 vs 运行库版本不匹配，可修
        解法  pkg upgrade，升级后 llama-cli 能正常启动
        残留  升级后 libc++_shared.so 仍不导出该符号（strings 查不到），
              但链接错误已消失，说明是别的库补齐了

问题 5  /tmp 在 Termux 里不可写
        现象  脚本里写 /tmp/vk.txt 报 Permission denied
        解法  Termux 应用 $TMPDIR，默认 /data/data/com.termux/files/usr/tmp

问题 6  PowerShell 5.1 读 UTF-8 无 BOM 的中文 .ps1 会乱码
        现象  The string is missing the terminator，行号指向莫名其妙的位置
        原因  PS 5.1 按系统 ANSI 代码页解析 .ps1
        解法  脚本存成 UTF-8 with BOM

问题 7  PowerShell 里 -split "`r?`n" 会破坏解析
        现象  同上，语法错误
        原因  反引号是转义引导符，`r 不是合法转义序列
        解法  写成 -split '\r?\n'（单引号正则）

问题 8  input text 无法输入 shell 重定向符号
        现象  bash script.sh > log 2> &1 被拆成 ... 2> 和 &1，
              报 syntax error near unexpected token `&'
        解法  改用 tee：bash script.sh | tee log
              管道符 | 和 tee 能正常输入

问题 9  /sdcard/Download 对 Termux 不可读
        现象  run-as com.termux cp /sdcard/Download/xxx 报 Permission denied
        原因  Android 11+ 的 FUSE 挂载需要存储权限，Termux 未获授权
        解法  改推到 /data/local/tmp/ 再拷进 Termux 私有目录
        注意  adb push 的目标若写成目录（结尾带 /）且源文件含中文名，
              文件名会被截断，必须写完整的文件名
```

## 七、文件清单

### 本次新增的探测与部署脚本

```text
项目根目录（两个成体系的脚本，各配同名文档）
    termux-gpu-setup.sh        + .doc.md    GPU 后端安装与验证
    termux-npu-probe.sh        + .doc.md    NPU 三层可达性验证

tools/
    # 电脑侧驱动
    probe-gpu-npu.ps1          + .doc.md    电脑侧驱动脚本，推送并执行第一轮探测
    termux-run.sh                           Termux 环境包装器（解决 run-as 无 PATH）

    # 手机侧第一轮：硬件能力与可达性
    gpu-npu-probe.sh           + .doc.md    硬件能力探测（纯 shell）
    gpu-npu-reach.sh           + .doc.md    可达性深探（三层递进）

    # 手机侧第二轮：逐层定位 GPU 卡点
    termux-fix-libcxx.sh                    修 libc++ 版本不匹配
    termux-backend-diag.sh                  诊断 ggml 后端加载失败
    termux-mali-attach.sh                   尝试把 Mali 接到 Termux 的 Vulkan
    termux-system-vulkan-test.sh            对比系统 loader 与 Termux loader
    termux-android-loader-test.sh           绝对路径链系统 loader
    termux-app-context-test.sh              App 进程内复测（否掉了我自己的假设）
    termux-copy-mali-driver.sh              复制 Mali 驱动进 /data 绕 namespace
    termux-mali-origin-fix.sh               按 $ORIGIN/../egl 摆目录（这一步修好了）
    termux-mali-dep-loop.sh                 自动补依赖链（卡在 libged.so 循环）

    # 手机侧：NPU 验证
    termux-nnapi-enum.sh                    NNAPI 枚举（第一版，库路径找错，留作过程记录）
    termux-nnapi-enum2.sh                   NNAPI 枚举（APEX 正确路径，成功）
    termux-nnapi-runtime-check.sh           检查现成运行时的 NNAPI 支持
    termux-npu-e2e.sh                       NNAPI 端到端（图未通过校验）
    termux-nnapi-abi-probe.sh               二分法探测 OperandType 布局（未成功）
```

### 手机上脚本的落点

```text
/data/data/com.termux/files/home/scripts/     全部手机侧脚本
/sdcard/Download/phone-deploy-k70e/           归档副本，手机上直接可看
```

每个脚本都配了同名中文 `.doc.md`。

### 原始日志（`probe-reports/`）

```text
probe-7LPRYTBYU8NRY5SC-20261009-152022.log    第一轮硬件探测完整输出（352 行）
appctx.log                                    App 进程内复测完整输出
gpu-setup-out.log                             GPU 安装与验证过程
fix-libcxx.log                                libc++ 修复过程
nnapi-runtime.log                             NNAPI 运行时检查
screen.png / screen2.png                      手机屏幕截图（验证注入生效）
```

## 八、下一步可选项（按性价比排序）

```text
选项 1  接受现状，用 CPU 跑 llama.cpp
        成本 零
        收益 立即可用。这台机器的 CPU 指令集比上次那台更全，
             预期速度不低于上次华为的 22 t/s 冷态水平

选项 2  用 Android NDK 编 llama.cpp 的 Vulkan 后端，拿 Mali
        成本 下载 NDK 约 1 GB + 交叉编译时间
        收益 prefill 明显变快；decode 未必（1.5B 是访存受限）
        风险 低。Mali 驱动确认完好，Vulkan 1.3 + compute 齐全

选项 3  走 LiteRT-LM 的 MediaTek NPU delegate 跑 LLM
        成本 高。要换模型格式（TFLite/ONNX 量化），
             要找到匹配 APU 780 的 delegate，且 Termux 内未必可行
        （MediaTek 公开侧只给 NP Converter 与 TFLite Shim API，
          完整 NPU runtime 要 NDA）
        收益 不确定。已有学术实测表明 NPU 在 decode 阶段反而不如 CPU
        建议 除非有明确需求，否则不建议投入

选项 4  用 Termux 的 llama-cpp-backend-opencl 试 Mali 的 OpenCL
        成本 低（3 MB 的包）
        收益 估计同样会落到软件实现或直接失败，
             因为 /vendor/lib64/libOpenCL.so 同样被 namespace 拒
        建议 可以花几分钟试，但期望值低

选项 5  把上次那份 Home Assistant 也迁过来
        成本 中。proot 方案已验证可行，照搬即可
        注意 本机是 Android 14，容器内的 Debian 版本与上次相同，
             那次遇到的 Python 版本限制依然存在
```

## 九、方法上的两条经验

**第一，文件权限位与 SELinux / linker namespace 是三道独立的门。** 本次全程靠「看权限位 + 真实 open 测试 + 读 namespace 描述」三重对照才没走错方向。典型例子是 `/dev/apusys`，权限位写着 `crw-rw-rw-` 看着人人可用，实际 `dd` 读一个字节直接被拒。

**第二，我自己的两次预判都被实测推翻了，两次都记了下来。** 一次是预判「NNAPI 对第三方应用关闭，设备数应为 0」，实测是 4；一次是预判「App 进程内的 namespace 包含 `/vendor/lib64`，之前 run-as 的结论可能是假象」，实测 App 进程内同样是 `(default)` namespace、同样被拒。**这两次都说明：在这类进程隔离问题上，只有真机实测算数，读文档和凭经验推演都不可靠。**
