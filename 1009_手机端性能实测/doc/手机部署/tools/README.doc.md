# tools/ 脚本索引（Redmi K70E 探测系列）

本文件是 `tools/` 目录下 GPU/NPU 探测系列脚本的总说明。每个脚本的详细说明见各自的 `.doc.md`；本文只讲**它们之间的关系与调用顺序**，以及为什么需要这么多脚本。

## 为什么有这么多个脚本

GPU/NPU 探测在这台机器上被证明是一个**逐层排除**的过程，每一层都要用一个新的实验去证伪前一个假设。所以脚本数量多不是冗余，是排查路径的固化。按执行顺序排：

```text
阶段一  能力探测：机器里有什么硬件
        gpu-npu-probe.sh            /dev 节点、sysfs、图形手册、厂商库、NNAPI 声明
        gpu-npu-reach.sh            同一个硬件换个身份看能不能用（三层递进）

阶段二  GPU 卡点定位：从「有 GPU」走到「为什么用不了」
        termux-fix-libcxx.sh        先修掉包与运行库不匹配的干扰项
        termux-backend-diag.sh      发现 ggml 后端加载失败，以及 llvmpipe 而非 Mali
        termux-mali-attach.sh       发现 /vendor/lib64 被 linker namespace 拒
        termux-system-vulkan-test.sh 发现系统 loader 与 Termux loader 是两套实现
        termux-android-loader-test.sh 试绝对路径链接系统 loader（未成功）
        termux-app-context-test.sh  在真正的 App 进程内复测，确认 namespace 是根本约束

阶段三  NPU 验证：从「枚举得到」走向「能不能算」
        termux-nnapi-enum.sh        第一次尝试，库路径找错（留作过程记录）
        termux-nnapi-enum2.sh       定位到 APEX 路径，成功枚举 4 个加速器
        termux-nnapi-runtime-check.sh 检查现成运行时有没有 NNAPI 后端
        termux-npu-e2e.sh           端到端建图执行（图未通过参数校验）
        termux-nnapi-abi-probe.sh   二分法探测 OperandType ABI 布局（未成功）
```

## 电脑侧 vs 手机侧

```text
电脑侧脚本（PowerShell）
    probe-gpu-npu.ps1       推送并执行 gpu-npu-probe.sh，把输出抓回本地存成报告
    termux-run.sh           推送进手机用，不是本机执行的

手机侧脚本（shell）
    其余全部，在 Termux 内执行

注意：termux-run.sh 虽然放在 tools/ 下，但它的运行位置是手机。
它把 HOME/PATH/TMPDIR/PREFIX 固化下来，因为 run-as 不设置这些变量，
不加它直接 run-as com.termux bash 会报 exec failed: Permission denied。
```

## 怎么从电脑驱动

```powershell
$adb = "D:\项目\手机部署\tools\platform-tools\adb.exe"
$s   = "7LPRYTBYU8NRY5SC"
$run = "/data/data/com.termux/files/home/scripts/termux-run.sh"

# 硬件能力探测
powershell -ExecutionPolicy Bypass -File tools\probe-gpu-npu.ps1

# 可达性深探（shell 身份）
& $adb -s $s push tools\gpu-npu-reach.sh /data/local/tmp/reach.sh
& $adb -s $s shell sh /data/local/tmp/reach.sh

# Termux 环境里跑任意脚本
& $adb -s $s shell "run-as com.termux $run shell 'bash /data/data/com.termux/files/home/scripts/<脚本>'"
```

## 想在 Termux App 进程内执行（而不是 run-as 环境）

有些结论只有在真正的 App 进程里才成立。两条通道，实测只有第二条能用：

```text
通道 A  RunCommandService 广播
        失败。RunCommandService 声明了 com.termux.permission.RUN_COMMAND
        （protectionLevel=dangerous），而 adb shell 既无法持有也无法代授，
        报 "Requires permission com.termux.permission.RUN_COMMAND"。

通道 B  input text 注入终端（可用）
        先 am start 把 Termux 拉到前台，input tap 点终端区域，
        再 input text 输入命令、input keyevent 66 回车。

        两个限制要注意：
          1. input text 无法输入 shell 重定向符号 > 和 &，
             写 "cmd > log 2>&1" 会报 syntax error near unexpected token `&'
             改用管道：cmd | tee log
          2. 空格要写成 %s（Android 11+ 的规则），
             也可以整串用单引号包起来直接写空格
```

## 这批脚本暴露的方法论

**文件权限位、SELinux 域、linker namespace 是三道独立的门。** 三道门任一不过，硬件就用不上，而 `ls -l` 只看得到第一道。

典型反例是 `/dev/apusys`：权限位写着 `crw-rw-rw-`，看上去人人可用，实际以 `u:r:runas_app:s0` 身份 `dd` 读一个字节直接被拒。

另一个反例是 `/vendor/lib64/hw/vulkan.mali.so`：文件属性 `-rw-r--r--` 完全可读，`stat` 拿得到大小，但 `dlopen` 被 linker namespace 拒绝。**这条路上「能 stat 到」和「能 dlopen」是两回事。**

所以本系列的每个探测脚本都坚持三件事：真实 open/dd 测试而不是只看权限位、把报错原文完整打印出来（namespace 描述就藏在报错里）、以及在不同身份下各跑一次做对照。

## 对应文件

```text
本文件                      tools/ 脚本索引
gpu-npu-probe.doc.md        第一轮硬件能力探测的详细说明
gpu-npu-reach.doc.md        第二轮可达性深探的详细说明
probe-gpu-npu.doc.md        电脑侧驱动脚本的详细说明
../GPU-NPU探测报告.md        完整结论与证据链
../termux-gpu-setup.doc.md  GPU 后端安装脚本说明
../termux-npu-probe.doc.md  NPU 三层验证脚本说明
```
