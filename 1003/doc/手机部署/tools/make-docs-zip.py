"""把部署文档与脚本打包成一个 zip（显式设置 UTF-8 文件名标志，避免中文名乱码）。"""
import sys
import zipfile
from datetime import datetime
from pathlib import Path

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])

# (归档内路径, 源文件)
FILES = [
    ("README.md", SRC / "README.md"),
    ("部署总结.md", SRC / "部署总结.md"),
    ("提速调研报告.md", SRC / "提速调研报告.md"),
    ("端侧优化与容器化调研.md", SRC / "端侧优化与容器化调研.md"),
    ("HomeAssistant构建文档.md", SRC / "HomeAssistant构建文档.md"),
    ("交接文档.md", SRC / "交接文档.md"),
    ("start-server.sh", SRC / "start-server.sh"),
    ("start-server.doc.md", SRC / "start-server.doc.md"),
    ("start-homeassistant.sh", SRC / "start-homeassistant.sh"),
    ("start-homeassistant.doc.md", SRC / "start-homeassistant.doc.md"),
    ("termux-llama-prebuilt.sh", SRC / "termux-llama-prebuilt.sh"),
    ("termux-llama-setup.sh", SRC / "termux-llama-setup.sh"),
    ("html/docs.html", SRC / ".docs-html" / "docs.html"),
    ("html/docs-handover.html", SRC / ".docs-html" / "docs-handover.html"),
    ("html/docs-readme.html", SRC / ".docs-html" / "docs-readme.html"),
    ("html/docs-summary.html", SRC / ".docs-html" / "docs-summary.html"),
    ("html/docs-speed.html", SRC / ".docs-html" / "docs-speed.html"),
    ("html/docs-optimize.html", SRC / ".docs-html" / "docs-optimize.html"),
    ("tools/deploy-to-phone.ps1", SRC / "tools" / "deploy-to-phone.ps1"),
    ("tools/md2html.py", SRC / "tools" / "md2html.py"),
    ("tools/md2html.doc.md", SRC / "tools" / "md2html.doc.md"),
    ("tools/make-docs-zip.py", SRC / "tools" / "make-docs-zip.py"),
    ("tools/make-docs-zip.doc.md", SRC / "tools" / "make-docs-zip.doc.md"),
    ("bench-server.ps1", SRC / "bench-server.ps1"),
    ("bench-server.doc.md", SRC / "bench-server.doc.md"),
    ("tools/mock-llama-server.py", SRC / "tools" / "mock-llama-server.py"),
    ("tools/mock-llama-server.doc.md", SRC / "tools" / "mock-llama-server.doc.md"),
]

STAMP = datetime.now().strftime("%Y-%m-%d %H:%M")

README_TXT = f"""手机端部署 1.5B 大模型 · 文档包
打包时间：{STAMP}
设备：华为 HBN-AL80（Android 12，8 核 16 GB，arm64-v8a）
状态：已部署完成并实测通过

================================================================
一、包里有什么
================================================================

README.md                    使用说明（怎么用、参数、常见问题）
部署总结.md                   项目总结（完整构建过程、验收结果、踩坑记录）
提速调研报告.md                提速调研：为什么 NPU/GPU 不可用、0.6B 实测收益、热降频数据
端侧优化与容器化调研.md         剪枝原理与为何对本机无用、手机部署 Docker 的可行性
HomeAssistant构建文档.md       在手机上不用 Docker 跑起 Home Assistant 的完整过程与六个坑
交接文档.md                   先看这个：当前状态、拔线后怎么用、两个模型怎么选
start-server.sh              服务启停脚本（放到手机后用这个启动）
start-server.doc.md          上面这个脚本的说明书
termux-llama-prebuilt.sh     全新手机的一键安装脚本（零编译）
termux-llama-setup.sh        旧路线脚本（手机内编译，当前会失败，仅作参考）

html/docs.html               文档入口网页（浏览器打开，自动跳转）
html/docs-readme.html        使用说明的网页版
html/docs-summary.html       部署总结的网页版

tools/md2html.py             Markdown 转网页的脚本（改完文档重新生成用）
tools/md2html.doc.md         上面这个脚本的说明书
tools/make-docs-zip.py       打这个压缩包的脚本
tools/make-docs-zip.doc.md   上面这个脚本的说明书
tools/deploy-to-phone.ps1    电脑端推送脚本（装 Termux + 推文件）

bench-server.ps1             分段计时工具：打手机服务，显示 prefill / decode / TTFT
tools/mock-llama-server.py   分段计时工具的离线测试替身（返回同构响应）
tools/mock-llama-server.doc.md  上面这个替身的说明书

（未收录 tools/termux-universal.apk，117 MB 的 Termux 安装包，
  需要的话去 https://f-droid.org/packages/com.termux/ 下载）


================================================================
二、手机上当前已经装好了什么（无需重装）
================================================================

  ~/llama-android/llama-b11146/   llama.cpp 可执行文件与依赖库（267 MB）
  ~/llama-android/ui/llama-b11146/ Web 聊天界面资源
  ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf   模型（1.04 GB）
  ~/.local/bin/                   22 个命令（llama-cli / llama-server 等）
  ~/start-server.sh               服务启停脚本
  ~/.bashrc                       已写入 PATH

所以这个包主要是文档和备用脚本，不是重装用的。


================================================================
三、怎么用（三种方式）
================================================================

1) 浏览器聊天界面（最省事）
   先启动服务：   bash ~/start-server.sh
   再打开浏览器： http://127.0.0.1:8080
   局域网其他设备：http://<手机IP>:8080

2) Termux 命令行对话
   llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 8 -c 2048
   退出用 /exit

   单次提问（答完自动退出）：
   llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 8 -c 2048 -n 128 -st -p "问题"

3) 当 API 用（OpenAI 兼容）
   curl http://127.0.0.1:8080/v1/chat/completions \\
     -H "Content-Type: application/json" \\
     -d '{{"messages":[{{"role":"user","content":"你好"}}],"max_tokens":128}}'

服务管理：
   bash ~/start-server.sh         启动
   bash ~/start-server.sh stop    停止
   bash ~/start-server.sh status  查看状态与地址


================================================================
四、实测性能
================================================================

  llama-cli 单轮     提示 60.2 t/s   生成 19.1 t/s
  llama-server HTTP  提示 57.8 t/s   生成 18.2 t/s

  模型加载后常驻内存约 1.9 GB，16 GB 内存余量充裕。


================================================================
五、四个必须知道的坑
================================================================

1. 别在手机上编译 llama.cpp
   会在链接阶段失败：
     ld.lld: error: undefined reference: std::__ndk1::__hash_memory(...)
   原因是 Termux 的 clang 21 与 llama.cpp 新版源码 libc++ ABI 不匹配。
   正确做法是用官方 Android arm64 预编译包。

2. 必须用 android-arm64，不要用 ubuntu-arm64
   两者指令集相同但 C 运行库不同：前者 bionic（Android 可用），
   后者 glibc（树莓派用，在 Android 上报 ld-linux-aarch64.so.1 not found）。

3. bionic linker 不支持 $ORIGIN RPATH
   直接运行解压出的二进制会报 library not found，必须设 LD_LIBRARY_PATH。
   本机已用 ~/.local/bin/llama-dispatcher 分发器自动处理。

4. Web 界面资源要单独装
   官方 Android 包不含内置 UI，缺失时浏览器报
   "Error: gzip is not supported by this browser"（HTTP 415）。
   需要 llama-b11146-ui.tar.gz 并用 --path 指向解压目录。
   start-server.sh 已包含该参数。

另外两个容易踩的：
   - llama-cli 是带边框的交互界面；llama-server 没有界面，它在监听 HTTP，别以为卡死
   - 单次提问必须加 -st；旧参数 -no-cnv 已被移除，用它会报 invalid argument


================================================================
六、如果换了新手机，怎么装
================================================================

1. 装 Termux（必须从 F-Droid 或 GitHub Releases，不要用 Google Play 版）
2. 把这个包里的 termux-llama-prebuilt.sh 传到手机
3. 在 Termux 里执行：
     bash ~/termux-llama-prebuilt.sh --model
   脚本会自动下载预编译包、校验 SHA256、装好命令、下载模型。

需要电脑远程操作手机时（USB 调试）：
   powershell -ExecutionPolicy Bypass -File tools\\deploy-to-phone.ps1
"""


def main():
    """命令行入口：argv[1] 为项目目录，argv[2] 为输出 zip 路径。

    逐个写入条目，每个条目都手工构造 ZipInfo 并设置 UTF-8 文件名标志位，
    这样中文文件名在 Windows 资源管理器与安卓解压器上都不会乱码。
    """
    missing = []  # 记录源文件缺失的条目，最后统一提示
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # 说明文件放最前，打开压缩包第一眼就能看到
        info = zipfile.ZipInfo("说明.txt", date_time=datetime.now().timetuple()[:6])
        info.flag_bits |= 0x800  # UTF-8 文件名标志
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16  # 权限位：普通文件
        z.writestr(info, README_TXT.encode("utf-8"))

        for arcname, path in FILES:
            if not path.exists():
                missing.append(str(path))
                continue
            zi = zipfile.ZipInfo(arcname, date_time=datetime.now().timetuple()[:6])
            zi.flag_bits |= 0x800  # 关键：让中文名在各平台都正确解码
            zi.compress_type = zipfile.ZIP_DEFLATED
            # .sh 脚本标记为可执行，解压后无需再 chmod
            zi.external_attr = (0o755 if path.suffix == ".sh" else 0o644) << 16
            z.writestr(zi, path.read_bytes())

    print(f"生成 {OUT}  ({OUT.stat().st_size} 字节)")
    if missing:
        print("缺失（已跳过）:")
        for m in missing:
            print("  " + m)


if __name__ == "__main__":
    main()
