# llm

大模型接入相关的东西都放这里。

## 本目录里我们自己的文件

```text
test_llm_fridge_local.py    冰箱那条测试的可运行副本（会真写真冰箱，跑完自己还原）
test_llm_fridge_local.md    上面这份脚本的说明：职责/输入/输出/与原文的差异
test_llm_surface_local.py   仓库 12 项测试的可运行副本（临时配置改写进临时目录）
test_llm_surface_local.md   上面这份脚本的说明：职责/输入/输出/差异
surface.out.log             环境变量注入那次的通过记录（stdout）
surface.err.log             同上，stderr（MCP server 的 INFO 日志）
surface_env.log             清空环境变量、只靠 ha_mcp_server\.env 那次的通过记录
surface_env.err.log         同上，stderr
```

日志被 `_work\.gitignore` 的 `*.log` 排除。

## 第三方代码（不逐个写文档）

```text
ext-2.0.3.zip / ext-2.0.2.zip                      从 GitHub release 下的包
extract\extended_openai_conversation-2.0.3\         2.0.3 解压结果（要求 HA ≥ 2026.10，本机不适用）
extract202\extended_openai_conversation-2.0.2\      2.0.2 解压结果（实际装到 HA 的就是它）
removed_extended_openai_conversation\               从 HA 撤下来的集成目录（留档，可移回）
```

这四个目录是别人的代码，不按"每份代码配同名 md"的规矩逐个写说明。它们的来源、版本选择依据、为什么撤下来，都记在 [_work\07_大模型接入与E路线实测.md](../07_大模型接入与E路线实测.md) 里。

## 版本选择的结论（一句话）

2.0.3 要求 HA ≥ 2026.10.0b0，2.0.2 只要求 ≥ 2026.3.0，而它依赖的 `openai~=2.21.0` 与 HA 2026.5.4 自带的版本完全一致，所以这台机器上用 2.0.2。
