# measure-phone-stream.py 中文说明

职责：测量真实 SSE 流从发起请求到首个非空 `content` 的时间，分别保存首事件、首思考、首答案及总耗时。不会把非流式 HTTP 的首包时间当成首字延迟。

控制台和归档文件使用UTF-8，兼容Windows中文终端与Termux。

输入：`--prompt-file` 是 UTF-8 文本，可含中文；`--expected-model` 是 `/v1/models` 中模型标识的片段；`--base-url` 默认为手机本机 8080，也可通过电脑 ADB 转发访问。模型标识必须结合服务启动日志核对真实文件，别名本身不能证明权重哈希。

```text
--endpoint chat       /v1/chat/completions，应用聊天模板
                      请求 enable_thinking=false，服务也应显式关闭思考
--endpoint completion /completion，裸文本负载，不应用聊天模板
--cache off/on        只控制 completion 的 cache_prompt
--repeat 5            同一请求重复 5 次；首轮与后续轮次分开分析
```

输出：新目录中的 `models.txt` 保存模型响应，`request.txt` 保存实际请求，`NNN-sse.log` 保存原始 SSE，`NNN-sse.txt` 保存完整答案、思考、usage/timings 及延迟，`results.tsv` 汇总每轮。缓存字段或服务吞吐字段缺失时留空，不凭客户端 chunk 数估算 token 数。

`prompt_tokens`取usage的完整提示词计数，裸completion则取`tokens_evaluated`；`evaluated_prompt_tokens`单独记录timings的`prompt_n`，它是本次处理部分，不能混写成总提示词长度。缓存计数依次读取usage的cached_tokens、裸completion的tokens_cached或timings的cache_n。字段缺失就留空。

`first_content_s` 是首个非空 content 事件的延迟；当服务器把思考文本混入 content 时，它会受到污染，应检查保存的答案。`first_event_s` 可能只是 role/空 delta；`first_reasoning_s` 来自独立 reasoning 字段。`after_first_wall_tps` 用 `(completion_tokens-1)/(total_s-first_content_s)` 近似，混合思考时只具参考意义，不能代替服务端纯 decode t/s。usage 缺失且 timings 无 token 数时不计算吞吐。

```bash
python ~/scripts/measure-phone-stream.py --expected-model Qwen3-0.6B --prompt-file ~/prompts/问答.txt --endpoint chat --out ~/stream-results/06-chat
python ~/scripts/measure-phone-stream.py --expected-model Qwen3-0.6B --prompt-file ~/prompts/缓存.txt --endpoint completion --cache on --out ~/stream-results/06-cache-on
```

读取：提示词、服务健康检查、模型接口和 SSE。写入：尚不存在的结果目录。不会启动/停止服务，不自动清缓存；chat 的冷请求要按主报告重启自己的实验服务，裸 completion 的缓存对比用 `--cache off/on`。

失败：模型不符、非 SSE 响应、无完整结束标志、返回错误或缺少可见答案，标记 FAILED 并退出码 1。网络 timeout 是单次 socket 读取超时；持续收到数据时总请求可能超过该值，不应当作总时长强杀器。`finish_reason=length` 表示回答达到输出上限，需要在质量验收中单独判定是否截断。

完整测量协议见 [手机小模型提速调研与复现.md](../手机小模型提速调研与复现.md)。
