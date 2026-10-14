# traj_replay.py

职责：

  把一条真实合成轨迹按 SFT 的消息口径重建出来，逐轮打到手机上的 llama-server，
  记录每轮的分段耗时（prefill / decode / TTFT / 缓存命中），用来回答
  「单轮等多久、一条轨迹跑多久、前缀缓存省多少」。

输入：

  `--host`         llama-server 地址，默认 `http://127.0.0.1:8080`（经 adb forward 打到手机）
  `--sample`       样本 id，取 `record.scenario_id`，默认 `sc_T1_001`
  `--mode`         `traj` 逐轮回放整条轨迹；`single` 只在最后一步的完整上下文上量一次
  `--max-tokens`   每轮最多生成多少 token，默认 32（真实数据里每轮 assistant 约 26 token）
  `--no-cache`     每次请求禁用前缀 KV 复用，用来做「无缓存」对照组
  `--warmup`       `none` 不预热；`short` 打一个 1 token 短请求（只为 CPU 升频）；
                   `system` 先把 system 段灌进 KV（真正的预热），默认 short
  `--skip-rounds N` 把前 N 步的完整上下文先打一次当预热（固定头进 KV），
                   计时从第 N 步开始。N=1 等于跳过 observe_home 那一步，
                   从它给出回答之后的下一步起算
  `--dry-run`      只打印将要发出的请求（步数、消息条数、字符数、末条角色），不连手机
  `--show`         只把这条轨迹摊开看（家、用户话、隐藏任务、逐轮交互），不连手机
  `--messages`     打印实际发给模型的消息清单，并检查家里状态有没有混进 prompt
  `--tag`          写日志时附加标签，例如模型名，避免不同模型的记录混在一起
  `--list`         列出轮数为 5 的 T1 样本，方便挑代表样本

输出：

  终端分段表（墙钟 / prompt tokens / 缓存命中 / prefill_ms / pp t/s /
  decode_ms / tg t/s / TTFT_ms），以及一行合计。
  原始记录写入 `_work\手机测评\logs\<样本>_<模式>_<cache|nocache>_<时间戳>.json`，
  `logs\` 已被 `_work\.gitignore` 排除，不入库。

读取：

  `D:\项目\autodl-tmp\new_demo\runs\quota200_20261004_v2\data_processed\D_dataset.jsonl`
  `D:\项目\autodl-tmp\new_demo\data_static\D0_templates\A_policy.md`

写入：

  只在 `logs\` 下写实测记录，不改数据集、不改仓库里的任何源文件。

不负责：

  不评测正确率（手机上跑的是未微调的原模型）；不构造新轨迹；不合并 LoRA。

对应文件：

  `_work\手机测评\tools\traj_replay.py`

口径说明：

  消息结构与 `training/10-5_sft/data.py` 的 `reconstruct_messages` 一致：
  system 用 A_policy 填入该样本记录的公开工具表，user 是 `scenario.user_request`，
  每轮 assistant 是工具调用 JSON，user 是 `"observation: " + last_tool_result`。
  逐轮回放时上下文始终取自**教师轨迹**，模型生成的内容只用于计时，不回填下一轮，
  这样每轮 prompt 长度与真实数据完全一致。

  每次测量前先打一个 1 token 的短请求预热（CPU 升频到位），数字代表持续使用的稳态。

运行示例：

```powershell
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --sample sc_T1_001 --show
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --sample sc_T1_001 --messages
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --sample sc_T1_001 --skip-rounds 1 --dry-run
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --host http://127.0.0.1:18080 --sample sc_T1_001 --skip-rounds 1
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --sample sc_T1_001 --mode traj
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --sample sc_T1_001 --mode traj --no-cache
D:\Anaconda\python.exe _work\手机测评\tools\traj_replay.py --sample sc_T1_001 --mode single --max-tokens 100
```

`--skip-rounds` 的语义：预热请求的 prompt 与要计时的第一步**完全相同**，
所以那一步的耗时会接近 0（前缀全命中）。这是「已经预热过」的效果；
预热本身的耗时会在输出里单列一行，不计进统计。

`--show` 的渲染规则：`observe_home` 只列房间名，`inspect_room` 列该房间的设备清单，
`inspect_device` 展开 state 与 actions（enum 写取值、数值写 min–max step），
`execute_action` 给 state_after 与 verified/changed，并单列 state_diff。这些正是模型每轮真正拿到的东西。
