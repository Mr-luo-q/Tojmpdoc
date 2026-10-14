# 手机部署 · CPU 性能实测报告（Redmi K70E）

实测日期：2026-10-09
设备：Redmi K70E（`duchamp`，2311DRK48C）
SoC：MediaTek MT6897 = 天玑 8300-Ultra
后端：llama.cpp 0.6.0，CPU（`-ngl 0`）
模型：Qwen2.5-1.5B-Instruct Q4_K_M、Qwen3-0.6B Q4_K_M，均与电脑端逐字节校验一致

## 一、这台机器的 CPU 拓扑（四种途径交叉确证）

```text
cluster_id=0   cpu0-3   2200 MHz   4 核 Cortex-A510
cluster_id=1   cpu4-6   3200 MHz   3 核 Cortex-A715
cluster_id=2   cpu7     3350 MHz   1 核 Cortex-A720

cpufreq policy 三份，与簇一一对应：
    policy0: cpus=0 1 2 3   max=2200MHz
    policy4: cpus=4 5 6     max=3200MHz
    policy7: cpus=7         max=3350MHz

CPU 特性（比上一台华为多了 sve2）：
    fp asimd aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm
    jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 sve sve2 sveaes
    svepmull svebitperm svesha3 svesm4 svei8mm svebf16 i8mm bf16
```

## 二、实测数据

### 2.1 首轮基准（`-t 8`，参数写错的一轮）

| 模型 | 测试 | t/s |
|---|---|---|
| Qwen2.5-1.5B | pp512 | 26.65 ± 0.86 |
| Qwen2.5-1.5B | tg128 | **6.93 ± 0.05** |
| Qwen3-0.6B | pp512 | 63.30 ± 0.76 |
| Qwen3-0.6B | tg128 | 17.07 ± 0.65 |

### 2.2 线程数扫描（`-ngl 0`，默认调度）

| 模型 | 指标 | `-t 4` | `-t 6` | `-t 8` |
|---|---|---|---|---|
| 1.5B | pp256 | 22.46 ± 0.06 | 21.50 ± 0.65 | 22.35 ± 0.14 |
| 1.5B | tg64 | **16.32 ± 0.04** | 11.31 ± 0.05 | 7.80 ± 0.13 |
| 0.6B | pp256 | 57.04 ± 0.22 | 56.05 ± 0.13 | 60.27 ± 0.17 |
| 0.6B | tg64 | **33.75 ± 0.25** | 17.34 ± 0.31 | 18.01 ± 0.04 |

**`tg` 随线程数增加而崩溃，`pp` 基本不变。** 加线程反而变慢，是访存带宽饱和的典型特征。

### 2.3 绑核实测（`taskset`，1.5B，`-ngl 0`）

| 绑定 | 线程 | pp128 | tg48 |
|---|---|---|---|
| cpu0-3（4×A510 2.2GHz） | 4 | 3.46 | 2.60 |
| cpu4-6（3×A715 3.2GHz） | 3 | 17.07 | 12.50 |
| cpu7（1×A720 3.35GHz） | 1 | 5.76 | 4.34 |
| cpu0-7（全部） | 8 | **24.23** | 8.13 |
| cpu4-7（中+大核） | 4 | 21.70 | **14.93** |

**关键事实：4 个小核跑推理几乎无用（tg 只有 2.60 t/s，是大核集群的 1/5）。** 这纠正了我此前的一个错误判断——我曾以为 `-t 4` 是"跑在小核上反而最快"，实际是调度器把线程放在了中/大核，绑核测试揭穿了这个混淆。

### 2.4 定稿配置对比

| 配置 | 1.5B pp256 | 1.5B tg64 | 0.6B pp256 | 0.6B tg64 |
|---|---|---|---|---|
| 默认 `-t 4` | 20.69 | 14.57 | 57.32 | 33.64 |
| 绑 cpu4-7 `-t 4` | 20.35 | 14.56 | 57.17 | 33.64 |
| 绑 cpu4-6 `-t 3` | 15.45 | 11.48 | — | — |

**默认调度与显式绑大核结果几乎完全一致**（tg 14.57 vs 14.56），说明调度器本来就把线程放在了中/大核上。**日常使用不需要 `taskset`，`-t 4` 即最优。**

### 2.5 推理期间的核心频率（决定性发现）

推理进行中，每 2 秒采样一次，**20 次读数完全一致**：

```text
cpu0 小核   1400 MHz   （上限 2200，用了 64%）
cpu4 中核   1800 MHz   （上限 3200，用了 56%）
cpu6 中核   1800 MHz
cpu7 大核   1800 MHz   （上限 3350，用了 54%）

同步观测：电池温度 28.1~37.4°C   ← 远低于热降频阈值
         low_power = 0            ← 省电模式未开
         AC powered = true        ← 插线供电
```

**推理时 CPU 被锁在硬件上限的 54~64%，且完全不动。** 这不是热降频（温度很低），也不是负载不足（正在跑推理）。

相关系统事实：

```text
scaling_driver = mtk-cpufreq-hw          MTK 硬件调频器，内核代理调频
init.svc.mi_thermald = running           小米温控守护进程在跑
init.svc.thermald = running
persist.sys.power.default.powermode = enhance    电源模式是「增强」而非「性能」
persist.sys.power_mode_support = true
persist.sys.smartop.support_dynamic_performance = false   动态性能关闭
ro.thermal.iec.enable = true
```

## 三、结论

**1. 这台机器的 CPU 推理性能被系统调频策略压制，不是 Termux 的问题，也不是参数问题。**

证据链完整：频率恒定在 54~64% + 温度低 + 省电未开 → 调频策略主动设限。

**2. 这解释了 pp 的异常偏低。** pp 是计算受限，性能与频率近似线性。若核心能跑满 3200MHz（当前 1800MHz），pp 理论上有 1.7 倍以上空间。

**3. 日常推荐参数：`-t 4`，纯 CPU，不需要 `taskset`。**

```bash
# 1.5B（质量优先）  pp 约 20 t/s   tg 约 15 t/s
llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 4 -c 2048

# 0.6B（速度优先）  pp 约 57 t/s   tg 约 34 t/s
llama-cli -m ~/models/Qwen3-0.6B-Q4_K_M.gguf -t 4 -c 2048
```

**4. 不要用 `-t 8`。** tg 会从 14.57 掉到 7.80，损失一半以上。这个坑很隐蔽，因为 `-t 8` 在最直觉的"用满 8 核"思路下看起来才对。

## 四、与上一台华为的对比（附保留意见）

| 指标 | 红米 K70E（天玑8300） | 华为 Pura 70（麒麟9010） | 差异 |
|---|---|---|---|
| 1.5B pp | 20.69（pp256） | 49.4~54.3（pp512） | 慢约 56% |
| 1.5B tg | 14.57~16.32 | 18.35~22.62 | 慢约 32% |
| 0.6B pp | 57.32（pp256） | 132.3~133.7 | 慢约 57% |
| 0.6B tg | 33.64~33.75 | 49.42~49.65 | 慢约 32% |

**必须说明的三点保留意见：**

```text
1. 提示词长度不同
   本机用 pp256，华为那台用 pp512。prefill 有固定开销，
   短提示词摊薄后 t/s 偏低。这个差异会夸大本机的劣势。

2. 不是同一次会话、不是同一台设备
   华为的数据来自上一个会话，环境条件（后台负载、温度、
   系统版本）无法复现，严格说不构成受控对比。

3. 本机的频率受限问题在华为那台上是否也存在，未知
   如果华为那台跑在满频而本机只有 54~64%，
   那这个对比反映的是「调频策略差异」而非「硬件性能差异」。
```

**因此：不能由这组数字断言天玑 8300 弱于麒麟 9010。** 唯一确定的结论是——**在本机当前的系统调频策略下，实测速度就是这个水平**。

## 五、可以试的改善方向（未验证）

```text
优先级 1  切到性能模式
          设置 → 电池 → 性能模式（当前是「增强」）
          persist.sys.power.default.powermode 现在是 enhance
          成本最低，值得先试

优先级 2  拔线跑一次
          厂商策略常在插电时压频。本次尝试过一次拔线对照，
          但因为我操作顺序错误（脚本还没推到手机就先拔线），
          没能拿到数据。
          正确顺序：先推脚本 → 再拔线 → 在 Termux 里手动执行

优先级 3  关闭后台应用
          实测后台常驻大量小米应用，swap 已用 1.6 GB。
          虽然 MemAvailable 有 6.9 GB（内存不是瓶颈），
          但后台活动可能影响调度器判断

优先级 4  接受现状
          `-t 4` 下 1.5B 约 15 t/s、0.6B 约 34 t/s，
          日常问答可用。0.6B 体验明显更好
```

**明确无法做的**：改 governor。`performance` governor 在可用列表里，但 `scaling_governor` 需 root 才能写。Termux 无 root，这条路封死。

## 六、方法上的一条教训

**我在这轮测试里犯了三个错误，都记录在此：**

```text
错误 1  以为 -t 4 是「用小核反而快」
        实际是调度器把线程放在了中/大核。绑核测试才揭穿。
        教训：不绑核就无法判断线程实际跑在哪里。

错误 2  由 dumpsys meminfo 的 "1572M free" 推断内存紧张
        实际 MemAvailable 有 6.9 GB，MemFree 低是因为 Linux
        把空闲内存拿去做页缓存。这是两回事。
        教训：判断内存压力要看 MemAvailable 或 free 的 available 列。

错误 3  拔线测试的脚本还没推到手机就先拔了线
        拔线后 adb 断开，脚本推不上去，白折腾一轮。
        教训：拔线才能跑的测试，必须先推脚本再拔线；
              或提前准备「用 input text 往终端注入命令」的通道。
```

另外一个通用教训：**这台机器上读温度、读 governor、读 /proc/meminfo 都有权限限制**（App 域看不到 `/sys/class/thermal`、`/sys/class/power_supply`，`dumpsys battery` 也读不到）。所以涉及这些的自动化检测都不可靠，必须留人工核对的余地。

## 七、对应文件

```text
tools/termux-bench-cpu.sh        首轮基准（-t 8，含对照说明）
tools/termux-bench-diagnose.sh   线程数扫描 + 内存假设验证
tools/termux-bench-taskset.sh    绑核实测（查出小核无用、pp 与 tg 方向相反）
tools/termux-bench-final.sh      定稿配置对比（确认 -t 4 最优）
tools/termux-freq-sample.sh      推理期间频率采样（查出频率锁定）
tools/termux-freq-diagnose.sh    频率限制成因排查
tools/termux-bench-battery.sh    插拔线对照（因操作顺序错误未取得数据）

手机上日志：
    ~/bench-cpu.log        首轮基准
    ~/bench-diag.log       线程扫描
    ~/bench-taskset.log    绑核实测
    ~/bench-final.log      定稿配置
    ~/freq-sample.log      频率采样
    ~/freq-diagnose.log    频率成因排查
```
