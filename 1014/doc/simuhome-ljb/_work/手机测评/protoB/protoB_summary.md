# protoB_summary.py

职责：

  遍历 `logs\` 下所有方案 B 的实测记录，逐条打印"每一步调了什么工具、引用的 device_id 或
  room_id 在本家真实存在还是编造"，最后统计第 0 跳是否达标。
  它对应 05 文档第 6 节的验收标准，是方案 B 的行为检查器。

输入：

  无命令行参数。读取 `logs\*protoB*.json` 与数据集里的真实 id 集合。

输出：

  终端逐条清单 + 一行统计："第 0 跳不达标 N / M 条"
  达标的定义：第 0 跳是 `inspect_room`，且引用的房间 id 真实存在。

读取：

  `_work\手机测评\logs\*protoB*.json`
  `D:\项目\autodl-tmp\...\D_dataset.jsonl`（只取 scenario.home 的 id 集合）

写入：

  不写任何文件。

不负责：

  不判对错、不评测正确率——只检查"有没有跳过必要观察、有没有编 id"。
  旧记录没有 model 字段时会显式标出。

对应文件：

  `_work\手机测评\protoB\protoB_summary.py`

运行示例：

```powershell
D:\Anaconda\python.exe _work\手机测评\protoB\protoB_summary.py
```
