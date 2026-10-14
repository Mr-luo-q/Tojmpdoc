# update_source.py 说明

## 功能

扫描工作区根目录，生成仓库根下的 `source.md`，内容包括三部分：

```text
1 本仓库跟踪的目录     名称、用途、大小、文件数、最后修改
2 不入库的外部目录     用途、大小、文件数、是否自带 .git、远端与版本
3 被忽略的大文件       PDF、安装包、wheel 的名称与体积
```

两张目录表的分工：进入 `TRACKED` 才会被 git 跟踪并出现在第 1 张表；退役或外部目录写进 `REGISTERED`，只登记体积与来源。
已退役的 `oldmcp`（早期 MCP 实验）就放在 `REGISTERED` 里，不再跟踪、不再作为参考材料。

## 输入 / 输出

```text
输入   工作区实际文件（无参数）
输出   覆盖写 D:\D_coderesource\simuhome\source.md，并打印一行统计
```

## 依赖与行为

```text
只依赖标准库（os、fnmatch、subprocess、datetime、pathlib）
对自带 .git 的子目录，调用 git 读取 remote / branch / 最近提交；读不到就写 (无远端)
遇到权限错误或无法访问的文件会跳过，不中断
扫描全量目录约 30 秒（工作区里有 20 万+ 文件的外部目录）
```

## 什么时候跑

```text
新增或删除顶层目录后
新增大文件（PDF、安装包）后
外部目录更新了版本（比如 ha_core_official 重新拉取）后
```
