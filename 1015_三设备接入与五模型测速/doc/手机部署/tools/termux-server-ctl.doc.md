# termux-server-ctl.sh 说明

配套脚本：[termux-server-ctl.sh](termux-server-ctl.sh)

## 职责

为电脑侧的评分脚本提供一个不依赖交互的 llama-server 启停入口：给定任意模型的绝对路径，
起服务、等健康检查、测完停掉。它不负责选题、判分与排名。

## 输入

```text
start <模型绝对路径> [端口] [off|on]   默认端口 8080，默认关闭思考
stop
wait <端口> [秒数]
status
```

## 输出

```text
start  → 先打印 pid=<进程号>，健康检查通过后打印 ready after <秒> 
         失败打印 timeout waiting for port <端口>
日志   → ~/eval-server.log（每次启动覆盖）
```

## 固定参数

```text
llama-server -m <模型> -t 4 -c 2048 -ngl 0
  --host 127.0.0.1 --port <端口>
  --jinja --reasoning off --parallel 1
```

`--parallel 1` 是为了让并发请求排队而不是并行抢占，评分时序列化请求才能保证每题耗时可比。

第三个位置参数给 `on` 时不传 `--reasoning off`，用于对照「关闭思考是否让算术题退化」。
开启思考后单题输出可能长达上千 token，评分脚本要相应放宽最大输出长度。

## 与 ~/start-server.sh 的分工

```text
start-server.sh        日常使用。模型名是 06/15/17/35 四个代号，
                       带 Web UI 路径、思考模式开关、局域网监听

termux-server-ctl.sh   被脚本调用。只认绝对路径，不读环境变量，
                       固定 127.0.0.1 + 单并发，输出机器可读
```

## 不负责

不下载模型，不改写 Termux 配置，不判断答案对错。
