# switch_and_probe.ps1

## 职责

一次跑完四步：把家用 Wi-Fi 的配置档临时改成手动 → 连到设备的配网热点 → 跑深度探测 → 无论成败都恢复原样。

为什么要把家用 Wi-Fi 设成手动：设备热点没有外网，Windows 会自作主张切回有外网的那张网，上一轮探测就是这么被打断的。

## 输入

```text
命令行    无参数
硬编码    $ap      设备热点 SSID（hzsj-light-wyra02_mibtF3E6）
          $homeSsid 家用 Wi-Fi SSID（pearcat）
```

## 输出

```text
[1/4] 把 <家用 SSID> 暂时设为手动连接 ...
[2/4] 连接到设备热点 <AP SSID> ...
      当前 SSID（netsh 输出）
[3/4] 开始深度探测 ...（probe_ap_deep.py 的全部输出）
[4/4] 恢复网络 ...
      当前 SSID
```

## 读取

`netsh wlan` 的当前状态。

## 写入

```text
改 Windows 的 Wi-Fi 配置档连接模式（manual ↔ auto）
切 Wi-Fi 网络再切回来
```

## 不负责

不判断探测结果，不在探测失败时跳过恢复（`finally` 保证恢复一定会跑），不处理家用 Wi-Fi 有多个配置档的情况。

## 一个真实踩过的坑

```text
变量名不能叫 $home —— 那是 PowerShell 的只读内置变量，
赋值会失败，导致"恢复网络"那步静默不执行。第一次跑就踩到了这个坑，
所以现在叫 $homeSsid。
```

## 失败时返回什么

`finally` 块不受探测结果影响，一定执行恢复。恢复后打印当前 SSID 供人工确认。

## 对应文件

```text
_work\xiaomi\switch_and_probe.ps1    本文件
_work\xiaomi\probe_ap_deep.py        第 3 步调用的探测脚本
_work\xiaomi\probe_lan.py            更早一版的局域网发现探针
```
