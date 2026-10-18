# compose.yaml

## 职责

沙盒专用 HA 容器的编排文件。它和仓库里的 `deploy\compose.yaml` 是两份独立的东西，本文件不动那一份。

## 与仓库那份的差异，以及为什么

```text
镜像   用本机已有的 homeassistant/home-assistant:stable
       不写 ghcr.io：本机 Docker Hub 与 ghcr 都不通，本地这份现成可用，省一次约 3 GB 拉取

配置目录  D:\homeassistant-sandbox
       不碰现有的 D:\homeassistant：那边是旧 REST 方案的配置，
       里面的 switch.simuhome_* 会和 MQTT discovery 生成的新实体撞名，
       HA 会给新实体加 _2 后缀，工具面和 e2e 用例都会对不上
```

## 输入

```text
环境变量  HA_CONFIG_DIR（必填）
          ${HA_CONFIG_DIR:?…} 的写法保证未设置时 compose 直接报错，
          避免误建一个空配置目录
```

## 输出

```text
容器      homeassistant，端口 8123:8123，时区 Asia/Shanghai，restart: unless-stopped
挂载      ${HA_CONFIG_DIR} → /config
```

## 读取

不读文件。配置全部内联。

## 写入

容器运行时会往挂载的配置目录写 `.storage\`、日志、数据库。

## 不负责

不含 broker、不含发布器、不含 SimuHome。这三样跑在宿主上，由 `_work\start_sandbox.ps1` 编排。

## 失败时返回什么

未设置 `HA_CONFIG_DIR` 时 compose 在解析阶段直接报错退出，不会启动容器。

## 对应文件

```text
_work\ha\compose.yaml        本文件
deploy\compose.yaml          仓库的通用版（只读，本文件不覆盖它）
_work\start_sandbox.ps1      用本文件 up -d
_work\stop_sandbox.ps1       用本文件 stop
```
