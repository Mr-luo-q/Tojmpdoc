# 1004_V2接入小米设计

主题：V2 接入小米后的设计方案：记忆模块、时间调度、交付接口（来源为 finally new paper 的 10_04 目录）

本目录共 16 个文件，来自 simuhome-ljb。“原路径”是它在来源工程里的位置。

## simuhome-ljb（16）

| 文件 | 原路径 | 大小 |
| --- | --- | --- |
| [01_V2设计方案.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/01_V2设计方案.md>) | `finally new paper/10_04V2接入小米后设计方案/01_V2设计方案.md` | 22.3 KB |
| [02_记忆模块分析与只读实现方案.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/02_记忆模块分析与只读实现方案.md>) | `finally new paper/10_04V2接入小米后设计方案/02_记忆模块分析与只读实现方案.md` | 10.1 KB |
| [03_记忆模块-长度格式与检索分析.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/03_记忆模块-长度格式与检索分析.md>) | `finally new paper/10_04V2接入小米后设计方案/03_记忆模块-长度格式与检索分析.md` | 15.1 KB |
| [04_记忆相关任务-四篇Bench梳理.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/04_记忆相关任务-四篇Bench梳理.md>) | `finally new paper/10_04V2接入小米后设计方案/04_记忆相关任务-四篇Bench梳理.md` | 8.7 KB |
| [05_规则与自动化相关内容梳理.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/05_规则与自动化相关内容梳理.md>) | `finally new paper/10_04V2接入小米后设计方案/05_规则与自动化相关内容梳理.md` | 17.1 KB |
| [06_本地1.5B模型部署与规则代码生成测试.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/06_本地1.5B模型部署与规则代码生成测试.md>) | `finally new paper/10_04V2接入小米后设计方案/06_本地1.5B模型部署与规则代码生成测试.md` | 6.6 KB |
| [07_MCP写入自动化规则-可行性分析与接口设计.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/07_MCP写入自动化规则-可行性分析与接口设计.md>) | `finally new paper/10_04V2接入小米后设计方案/07_MCP写入自动化规则-可行性分析与接口设计.md` | 10.1 KB |
| [08_两篇Bench英文工具名与参数名对照.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/08_两篇Bench英文工具名与参数名对照.md>) | `finally new paper/10_04V2接入小米后设计方案/08_两篇Bench英文工具名与参数名对照.md` | 10.4 KB |
| [09_一次性调度与持久化调度-两个通用语义接口.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/09_一次性调度与持久化调度-两个通用语义接口.md>) | `finally new paper/10_04V2接入小米后设计方案/09_一次性调度与持久化调度-两个通用语义接口.md` | 9.0 KB |
| [14_记忆与时间调度接口详细设计.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/14_记忆与时间调度接口详细设计.md>) | `finally new paper/10_04V2接入小米后设计方案/14_记忆与时间调度接口详细设计.md` | 22.4 KB |
| [15_目前方案与交付接口.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/15_目前方案与交付接口.md>) | `finally new paper/10_04V2接入小米后设计方案/15_目前方案与交付接口.md` | 15.5 KB |
| [16_四个Bench任务类型梳理.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/16_四个Bench任务类型梳理.md>) | `finally new paper/10_04V2接入小米后设计方案/16_四个Bench任务类型梳理.md` | 7.7 KB |
| [README.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/README.md>) | `finally new paper/10_04V2接入小米后设计方案/README.md` | 4.6 KB |
| [09_国内可买到Matter小型设备调研.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/辅助调研文档/09_国内可买到Matter小型设备调研.md>) | `finally new paper/10_04V2接入小米后设计方案/辅助调研文档/09_国内可买到Matter小型设备调研.md` | 10.7 KB |
| [10_美的设备HA接入方案调研.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/辅助调研文档/10_美的设备HA接入方案调研.md>) | `finally new paper/10_04V2接入小米后设计方案/辅助调研文档/10_美的设备HA接入方案调研.md` | 11.2 KB |
| [README.md](<doc/simuhome-ljb/finally%20new%20paper/10_04V2接入小米后设计方案/辅助调研文档/README.md>) | `finally new paper/10_04V2接入小米后设计方案/辅助调研文档/README.md` | 383 B |
