# probe_api.py

## 职责

看清 bleak 的 `discover()` 在**当前这台机器**上返回什么形状：版本、函数签名、返回类型、以及第一个元素长什么样。

存在的理由：同一份 `scan.py` 在 Windows 上拿到的是 `dict {address: (device, adv)}`，在树莓派的 bleak 0.11.0 上却是 `list[BLEDevice]`（`return_adv` 被忽略、没有广播数据）。写兼容分支之前，先把形状量出来，而不是猜。

## 输入

```text
命令行    无参数
依赖      bleak
```

## 输出

```text
bleak 版本         有 __version__ 才打得出来，新版可能没有这个属性
discover 签名      inspect.signature 的结果，能直接看出 return_adv 在不在参数里
返回类型            dict 还是 list
元素形状            dict 打键样例与值类型；list 打元素类型与元组里各项的类型
```

## 读取 / 写入

只读广播（一次 6 秒扫描）。不连接、不配对、不写任何东西。

## 不负责

不做兼容处理，不解析厂商数据，不判断设备类型。它只回答"形状是什么"，兼容由 `scan.py` 与 `watch.py` 负责。

## 实测（2026-10-12，树莓派）

```text
bleak 版本: 0.11.0
discover 签名: (timeout=5.0, **kwargs) -> List[bleak.backends.device.BLEDevice]
返回类型: list
长度: 46
元素类型: BLEDevice
元素内容: 3D:74:DB:A8:80:05: 3D-74-DB-A8-80-05
```

结论：0.11.0 里 `return_adv` 不起作用，拿不到广播数据，必须走 `detection_callback`。这条直接决定 `scan.py` / `watch.py` 的写法。

## 对应文件

```text
_work\ble\probe_api.py    本文件
_work\ble\scan.py         按本探针的结论改成了回调式扫描
_work\ble\watch.py        同上
_work\pi\ssh_run.py       把本文件传到树莓派并跑它用的工具
```
