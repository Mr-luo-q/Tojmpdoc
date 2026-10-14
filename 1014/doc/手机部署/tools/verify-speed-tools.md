# verify-speed-tools.py 中文说明

职责：离线验证基准编排、失败记录和流式HTTP协议，防止复现工具产生错误性能结论；核对取证原文SHA-256。不会运行手机模型或生成新的手机速度。

输入：三份本地工具源文件；`--sources`指定来源归档，默认 `research/speed-20261014/sources`。读取全量和部分重试清单，后者按来源编号覆盖当前状态。

输出：UTF-8标准输出中的来源哈希核验数量、12项unittest结果，退出码0表示全部通过。测试使用临时目录和仅绑定127.0.0.1的HTTP服务，退出后清理。基准进程采用显式mock，SSE采用真实本机HTTP传输，固定测试数字均属于夹具，不是模型测试成绩。包含候选失败行保留、NaN/Infinity吞吐拒绝检查，以及完整提示词/实际处理token/缓存token分开统计。

```text
参数/计划 → CPU控制、深度、FA/KV单变量
结果归档 → ABBA顺序、空基线拒绝、超时保存原文
SSE协议  → 空role、reasoning、UTF-8答案、usage、结束标志
异常路径 → 非SSE拒绝、模型不符拒绝
来源完整 → 对照manifest的SHA-256
```

```powershell
python tools/verify-speed-tools.py
```

读取：本地代码、来源清单和原文。写入：临时文件；打开短时本机端口。不负责手机内核是否实际命中、NDK构建成功、温度取证或真实答案质量。
