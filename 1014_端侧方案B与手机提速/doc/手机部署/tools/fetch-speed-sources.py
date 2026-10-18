#!/usr/bin/env python3
# 调研取证模块：下载官方文档和源码，保留原文、内容哈希和失败记录。
import argparse
import base64
import concurrent.futures
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

LLAMA_REF = "091b6a7fc561b78da90a0ed2d524ec995458c657"
# 来源清单模块：GitHub 文件优先使用固定提交，其他来源记录实际内容哈希。
SOURCES = [
    ("S01", "llama-bench 用法", "gh", "ggml-org/llama.cpp", "tools/llama-bench/README.md", LLAMA_REF),
    ("S02", "llama-bench 实现", "gh", "ggml-org/llama.cpp", "tools/llama-bench/llama-bench.cpp", LLAMA_REF),
    ("S03", "llama-server 接口与参数", "gh", "ggml-org/llama.cpp", "tools/server/README.md", LLAMA_REF),
    ("S04", "ARM CPU 构建选项", "gh", "ggml-org/llama.cpp", "ggml/src/ggml-cpu/CMakeLists.txt", LLAMA_REF),
    ("S05", "ARM 权重重排实现", "gh", "ggml-org/llama.cpp", "ggml/src/ggml-cpu/repack.cpp", LLAMA_REF),
    ("S06", "Android 构建说明", "gh", "ggml-org/llama.cpp", "docs/android.md", LLAMA_REF),
    ("S07", "OpenCL 后端边界", "gh", "ggml-org/llama.cpp", "docs/backend/OPENCL.md", LLAMA_REF),
    ("S08", "推测解码", "gh", "ggml-org/llama.cpp", "examples/speculative/README.md", LLAMA_REF),
    ("S09", "MNN 项目与 LLM", "gh", "alibaba/MNN", "README.md", "master"),
    ("S10", "MLC Android 部署", "gh", "mlc-ai/mlc-llm", "docs/deploy/android.rst", "main"),
    ("S11", "ExecuTorch 项目和后端", "gh", "pytorch/executorch", "README.md", "main"),
    ("S12", "LiteRT-LM 支持平台", "gh", "google-ai-edge/LiteRT-LM", "README.md", "main"),
    ("S13", "Termux llama-cpp 包配方", "gh", "termux/termux-packages", "packages/llama-cpp/build.sh", "master"),
    ("S14", "Qwen3 模板和思考控制", "gh", "QwenLM/Qwen3", "README.md", "main"),
    ("S15", "Dimensity 8300 官方规格", "url", "https://www.mediatek.com/products/smartphones/mediatek-dimensity-8300", "", ""),
    ("S16", "Android NNAPI 状态（官方中国镜像）", "url", "https://developer.android.google.cn/ndk/guides/neuralnetworks", "", ""),
    ("S17", "Android 热状态 API（官方中国镜像）", "url", "https://developer.android.google.cn/games/optimize/adpf/thermal", "", ""),
    ("S18", "Qwen3-0.6B 官方配置", "url", "https://hf-mirror.com/Qwen/Qwen3-0.6B/raw/main/config.json", "", ""),
    ("S19", "Qwen2.5-1.5B 官方配置", "url", "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct/raw/main/config.json", "", ""),
    ("S20", "旧报告引用的 NPU 论文", "url", "https://arxiv.org/html/2607.05475", "", ""),
    ("S21", "已安装版基准实现", "gh", "ggml-org/llama.cpp", "tools/llama-bench/llama-bench.cpp", "v0.6.0"),
    ("S22", "已安装版参数实现", "gh", "ggml-org/llama.cpp", "common/arg.cpp", "v0.6.0"),
    ("S23", "已安装版 ARM 构建", "gh", "ggml-org/llama.cpp", "ggml/src/ggml-cpu/CMakeLists.txt", "v0.6.0"),
    ("S24", "MNN LLM 配置和量化", "gh", "alibaba/MNN", "docs/transformers/llm.md", "master"),
    ("S25", "MNN LLM 构建", "gh", "alibaba/MNN", "transformers/README.md", "master"),
    ("S26", "LiteRT-LM Android API", "gh", "google-ai-edge/LiteRT-LM", "docs/api/kotlin/getting_started.md", "main"),
    ("S27", "KleidiAI 量化内核选择", "gh", "ggml-org/llama.cpp", "ggml/src/ggml-cpu/kleidiai/kleidiai.cpp", LLAMA_REF),
    ("S28", "ExecuTorch XNNPACK 后端", "gh", "pytorch/executorch", "docs/source/backends/xnnpack/xnnpack-overview.md", "main"),
    ("S29", "llama.cpp 构建与 KleidiAI", "gh", "ggml-org/llama.cpp", "docs/build.md", LLAMA_REF),
    ("S30", "LiteRT-LM NPU 设备支持", "url", "https://ai.google.dev/edge/litert/next/litert_lm_npu", "", ""),
]


def download(url):
    # 用 curl 的参数数组下载，避免把 URL 拼进 shell 并保留网络错误。
    result = subprocess.run(["curl", "-sSL", "--fail", "--max-time", "20", "--retry", "1",
                             "-H", "User-Agent: phone-speed-research", url], capture_output=True, timeout=48)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def fetch_one(source, output):
    # 单一来源取证：固定 ref 失败时允许分支回退，但明确记录，绝不冒充固定版本。
    sid, title, kind, target, path, ref = source
    errors = []
    refs = [ref, "master"] if kind == "gh" and ref == LLAMA_REF else [ref]
    for actual_ref in refs:
        url = f"https://api.github.com/repos/{target}/contents/{path}?ref={actual_ref}" if kind == "gh" else target
        try:
            payload = download(url)
            blob_sha = ""
            if kind == "gh":
                metadata = json.loads(payload)
                blob_sha = metadata["sha"]
                payload = base64.b64decode(metadata["content"])
                (output / f"{sid}-metadata.txt").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
            saved = output / f"{sid}.txt"
            saved.write_bytes(payload)
            canonical = f"https://github.com/{target}/blob/{actual_ref}/{path}" if kind == "gh" else target
            return [sid, title, "OK", canonical, actual_ref, blob_sha, hashlib.sha256(payload).hexdigest(),
                    len(payload), saved.name, datetime.now(timezone.utc).isoformat(), " | ".join(errors)]
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{url}: {exc}")
    return [sid, title, "FAILED", url, ref, "", "", 0, "", datetime.now(timezone.utc).isoformat(), " | ".join(errors)]


def main():
    # 命令行入口：汇总所有来源，未取到的资料作为失败行写入清单。
    parser = argparse.ArgumentParser(description="归档手机模型提速调研来源")
    parser.add_argument("--out", type=Path, default=Path("research/speed-20261014/sources"))
    parser.add_argument("--only", help="仅下载逗号分隔的来源编号")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    selected = set(args.only.split(",")) if args.only else None
    sources = [s for s in SOURCES if selected is None or s[0] in selected]
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(fetch_one, source, args.out) for source in sources]
        for future in concurrent.futures.as_completed(futures):
            row = future.result()
            rows.append(row)
            print(f"{row[0]} {row[2]} {row[1]}", flush=True)
    manifest = args.out / ("manifest.tsv" if selected is None else "manifest-selected.tsv")
    with manifest.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(["id", "title", "status", "url", "ref", "blob_sha", "sha256", "bytes", "file", "fetched_utc", "errors"])
        writer.writerows(sorted(rows))
    write_index(args.out, rows, selected is not None)
    return int(any(row[2] == "FAILED" for row in rows))


def write_index(output, rows, partial):
    # 索引模块：把全量及部分重试清单合并显示，既保存原始失败记录也标明当前取证状态。
    merged = {}
    full = output / "manifest.tsv"
    if partial and full.exists():
        with full.open(encoding="utf-8", newline="") as stream:
            for row in csv.reader(stream, delimiter="\t"):
                if row and row[0] != "id":
                    merged[row[0]] = row
    merged.update({row[0]: row for row in rows})
    content = ["# 手机小模型提速来源索引", "", "取证日期：2026-10-14。原文是文档/源码归档，不是手机实测结果。",
               "", "GitHub文件保留ref与blob SHA，网页保留内容SHA-256与UTC时间。来源分支可能移动，应以本目录原文为准。完整清单见 sources/manifest.tsv；部分重试见 sources/manifest-selected.tsv。",
               "", "| 编号 | 中文说明及原始URL | 状态 | 本地原文 |", "|---|---|---|---|"]
    for sid, row in sorted(merged.items()):
        local = f"[归档](sources/{row[8]})" if row[2] == "OK" else "未取到，不能当作已核验依据"
        content.append(f"| {sid} | [{row[1]}]({row[3]}) | {row[2]} | {local} |")
    content += ["", "## 配置数据说明", "", "S18是官方Qwen3-0.6B配置的HF镜像归档：28层、隐藏维1024、查询头16、KV头8、head_dim128、词表151936、最大位置40960。S19是Qwen2.5-1.5B-Instruct配置：28层、隐藏维1536、查询头12、KV头2、词表151936、最大位置32768。两者均共享输入/输出嵌入，并关闭滑动窗口。它们是模型架构资料，不能代替实际GGUF权重校验。",
                "", "## 已知取证限制", "", "raw.githubusercontent.com和huggingface.co直连曾失败；GitHub内容API、官方Android中国镜像和HF镜像可用。API blob SHA及下载内容SHA-256已留存。S30设备支持页若FAILED，保留错误并将APU780适配标为待确认。", ""]
    (output.parent / "来源索引.md").write_text("\n".join(content), encoding="utf-8")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
