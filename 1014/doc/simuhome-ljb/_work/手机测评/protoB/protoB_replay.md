# protoB_replay.py

职责：

  方案 B 的原理验证脚本。把 `A_policy` 的改写全部放在内存里完成——工具表去掉 observe_home、
  改掉那一行说明、把房间信息作为一条独立消息插在用户话之前——再打到手机上的 llama-server，
  回答"这种形态模型还能不能往下走、单跳要多久"。

  与主线完全隔离：不改 `A_policy.md`、不改工具表、不改 D5 管线、不改数据集。

输入：

  `--host`        llama-server 地址，默认 `http://127.0.0.1:18080`
  `--sample`      样本 id，取 `record.scenario_id`，默认 `sc_T1_001`
  `--home-level`  `rooms` 只给房间（等同 observe_home 的回答）；`full` 再给每个房间的
                  设备 id / 名称 / 类型（不给状态与动作），默认 rooms
  `--max-tokens`  每跳生成上限，默认 32
  `--no-prewarm`  不预热固定块，做对照
  `--no-cache`    禁用前缀 KV 复用
  `--dry-run`     只打印 system 的改动与将发的消息，不连手机
  `--tag`         写日志时附加标签

输出：

  终端：固定块预热耗时一行、每跳生成的内容开头、分段耗时表、
        跳数 / prefill 合计 / 墙钟合计 / 含预热总账 / 单跳平均
  `_work\手机测评\logs\<样本>_protoB_<home级>_<标签>_<时间戳>.json`
  日志里带 `model` 字段（开跑时向服务端问的），避免以后分不清哪份记录是哪个模型

读取：

  `D:\项目\autodl-tmp\new_demo\runs\quota200_20261004_v2\data_processed\D_dataset.jsonl`
  `D:\项目\autodl-tmp\new_demo\data_static\D0_templates\A_policy.md`

写入：

  只在 `logs\` 下写实测记录；不写任何仓库源文件。

不负责：

  不改主线协议；不生成新数据；不评测正确率（手机上跑的是未微调原模型）。

对应文件：

  `_work\手机测评\protoB\protoB_replay.py`

口径说明：

  消息结构 = `[system' , home 块 , 用户话]` + 教师轨迹里 observe_home **之后**的往返。
  第一跳原本是 observe_home，方案 B 里被 home 块替代，所以计时从"模型该输出 inspect_room"
  那一步开始。

  固定块 = `[system' + home 块]`，这一段与用户那句话无关，是方案 B 里唯一可能跨任务共享的部分；
  预热它就是测"按家共享"能省多少。

系统提示词的改动：

```text
删掉   observe_home     只有房间 id 和名称；没有设备、没有温湿度
换成   （本家的房间与设备清单已在对话开头的 home 块里给出，不必再查询）
工具   5 个 -> 4 个（去掉 observe_home）
长度   2846 字符（5 工具）-> 2689 字符（4 工具）
```

运行示例：

```powershell
# 离线看改动与消息构造
D:\Anaconda\python.exe _work\手机测评\protoB\protoB_replay.py --sample sc_T1_001 --dry-run

# 真机：rooms 级
D:\Anaconda\python.exe _work\手机测评\protoB\protoB_replay.py --host http://127.0.0.1:18080 --sample sc_T1_001 --home-level rooms

# 真机：full 级（连设备 id 一起给）
D:\Anaconda\python.exe _work\手机测评\protoB\protoB_replay.py --host http://127.0.0.1:18080 --sample sc_T1_001 --home-level full
```
