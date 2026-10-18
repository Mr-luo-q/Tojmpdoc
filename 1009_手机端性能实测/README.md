# 1009_手机端性能实测

主题：手机端性能实测（CPU / GPU-NPU 探测与报告）、交接文档、四模型对比

本目录共 70 个文件，来自 手机部署、树莓派。“原路径”是它在来源工程里的位置。

## 手机部署（69）

| 文件 | 原路径 | 大小 |
| --- | --- | --- |
| [CPU性能实测报告.md](<doc/手机部署/CPU性能实测报告.md>) | `CPU性能实测报告.md` | 9.1 KB |
| [Enable-ICS.bat](<doc/手机部署/Enable-ICS.bat>) | `Enable-ICS.bat` | 2.2 KB |
| [Enable-ICS.reg](<doc/手机部署/Enable-ICS.reg>) | `Enable-ICS.reg` | 903 B |
| [GPU-NPU加速实测报告.md](<doc/手机部署/GPU-NPU加速实测报告.md>) | `GPU-NPU加速实测报告.md` | 14.1 KB |
| [GPU-NPU探测报告.md](<doc/手机部署/GPU-NPU探测报告.md>) | `GPU-NPU探测报告.md` | 27.5 KB |
| [Revert-ICS.reg](<doc/手机部署/Revert-ICS.reg>) | `Revert-ICS.reg` | 516 B |
| [Setup-Ethernet.bat](<doc/手机部署/Setup-Ethernet.bat>) | `Setup-Ethernet.bat` | 2.4 KB |
| [Token速率详表.md](<doc/手机部署/Token速率详表.md>) | `Token速率详表.md` | 25.3 KB |
| [appctx.log](<doc/手机部署/probe-reports/appctx.log>) | `probe-reports/appctx.log` | 9.1 KB |
| [fix-libcxx.log](<doc/手机部署/probe-reports/fix-libcxx.log>) | `probe-reports/fix-libcxx.log` | 4.9 KB |
| [gpu-setup-out.log](<doc/手机部署/probe-reports/gpu-setup-out.log>) | `probe-reports/gpu-setup-out.log` | 5.1 KB |
| [nnapi-runtime.log](<doc/手机部署/probe-reports/nnapi-runtime.log>) | `probe-reports/nnapi-runtime.log` | 4.1 KB |
| [perf-lean-1.5B-prefill.log](<doc/手机部署/probe-reports/perf-lean-1.5B-prefill.log>) | `probe-reports/perf-lean-1.5B-prefill.log` | 2.1 KB |
| [probe-7LPRYTBYU8NRY5SC-20261009-152022.log](<doc/手机部署/probe-reports/probe-7LPRYTBYU8NRY5SC-20261009-152022.log>) | `probe-reports/probe-7LPRYTBYU8NRY5SC-20261009-152022.log` | 15.1 KB |
| [termux-gpu-setup.doc.md](<doc/手机部署/termux-gpu-setup.doc.md>) | `termux-gpu-setup.doc.md` | 4.4 KB |
| [termux-gpu-setup.sh](<doc/手机部署/termux-gpu-setup.sh>) | `termux-gpu-setup.sh` | 8.8 KB |
| [termux-npu-probe.doc.md](<doc/手机部署/termux-npu-probe.doc.md>) | `termux-npu-probe.doc.md` | 5.3 KB |
| [termux-npu-probe.sh](<doc/手机部署/termux-npu-probe.sh>) | `termux-npu-probe.sh` | 10.7 KB |
| [README.doc.md](<doc/手机部署/tools/README.doc.md>) | `tools/README.doc.md` | 5.2 KB |
| [gpu-npu-probe.doc.md](<doc/手机部署/tools/gpu-npu-probe.doc.md>) | `tools/gpu-npu-probe.doc.md` | 3.5 KB |
| [gpu-npu-probe.sh](<doc/手机部署/tools/gpu-npu-probe.sh>) | `tools/gpu-npu-probe.sh` | 6.0 KB |
| [gpu-npu-reach.doc.md](<doc/手机部署/tools/gpu-npu-reach.doc.md>) | `tools/gpu-npu-reach.doc.md` | 3.6 KB |
| [gpu-npu-reach.sh](<doc/手机部署/tools/gpu-npu-reach.sh>) | `tools/gpu-npu-reach.sh` | 6.7 KB |
| [probe-gpu-npu.doc.md](<doc/手机部署/tools/probe-gpu-npu.doc.md>) | `tools/probe-gpu-npu.doc.md` | 2.5 KB |
| [probe-gpu-npu.ps1](<doc/手机部署/tools/probe-gpu-npu.ps1>) | `tools/probe-gpu-npu.ps1` | 3.2 KB |
| [termux-android-loader-test.sh](<doc/手机部署/tools/termux-android-loader-test.sh>) | `tools/termux-android-loader-test.sh` | 5.3 KB |
| [termux-app-context-test.sh](<doc/手机部署/tools/termux-app-context-test.sh>) | `tools/termux-app-context-test.sh` | 6.7 KB |
| [termux-backend-diag.sh](<doc/手机部署/tools/termux-backend-diag.sh>) | `tools/termux-backend-diag.sh` | 6.9 KB |
| [termux-bench-battery.sh](<doc/手机部署/tools/termux-bench-battery.sh>) | `tools/termux-bench-battery.sh` | 5.1 KB |
| [termux-bench-cpu.sh](<doc/手机部署/tools/termux-bench-cpu.sh>) | `tools/termux-bench-cpu.sh` | 5.2 KB |
| [termux-bench-diagnose.sh](<doc/手机部署/tools/termux-bench-diagnose.sh>) | `tools/termux-bench-diagnose.sh` | 5.4 KB |
| [termux-bench-final.sh](<doc/手机部署/tools/termux-bench-final.sh>) | `tools/termux-bench-final.sh` | 5.1 KB |
| [termux-bench-taskset.sh](<doc/手机部署/tools/termux-bench-taskset.sh>) | `tools/termux-bench-taskset.sh` | 7.0 KB |
| [termux-cleanup-bench.sh](<doc/手机部署/tools/termux-cleanup-bench.sh>) | `tools/termux-cleanup-bench.sh` | 2.7 KB |
| [termux-cmp2.sh](<doc/手机部署/tools/termux-cmp2.sh>) | `tools/termux-cmp2.sh` | 3.6 KB |
| [termux-compare-backends.sh](<doc/手机部署/tools/termux-compare-backends.sh>) | `tools/termux-compare-backends.sh` | 7.5 KB |
| [termux-compare-models.sh](<doc/手机部署/tools/termux-compare-models.sh>) | `tools/termux-compare-models.sh` | 4.3 KB |
| [termux-copy-mali-driver.sh](<doc/手机部署/tools/termux-copy-mali-driver.sh>) | `tools/termux-copy-mali-driver.sh` | 7.3 KB |
| [termux-fix-libcxx.sh](<doc/手机部署/tools/termux-fix-libcxx.sh>) | `tools/termux-fix-libcxx.sh` | 5.2 KB |
| [termux-freq-diagnose.sh](<doc/手机部署/tools/termux-freq-diagnose.sh>) | `tools/termux-freq-diagnose.sh` | 6.7 KB |
| [termux-freq-sample.sh](<doc/手机部署/tools/termux-freq-sample.sh>) | `tools/termux-freq-sample.sh` | 4.0 KB |
| [termux-get-models.sh](<doc/手机部署/tools/termux-get-models.sh>) | `tools/termux-get-models.sh` | 3.1 KB |
| [termux-gguf-arch.sh](<doc/手机部署/tools/termux-gguf-arch.sh>) | `tools/termux-gguf-arch.sh` | 5.5 KB |
| [termux-gpu-only-bench.sh](<doc/手机部署/tools/termux-gpu-only-bench.sh>) | `tools/termux-gpu-only-bench.sh` | 3.1 KB |
| [termux-gpu-scan.sh](<doc/手机部署/tools/termux-gpu-scan.sh>) | `tools/termux-gpu-scan.sh` | 4.0 KB |
| [termux-gpu-vs-cpu.sh](<doc/手机部署/tools/termux-gpu-vs-cpu.sh>) | `tools/termux-gpu-vs-cpu.sh` | 3.1 KB |
| [termux-http-timing.sh](<doc/手机部署/tools/termux-http-timing.sh>) | `tools/termux-http-timing.sh` | 5.5 KB |
| [termux-install-ui.sh](<doc/手机部署/tools/termux-install-ui.sh>) | `tools/termux-install-ui.sh` | 3.6 KB |
| [termux-mali-attach.sh](<doc/手机部署/tools/termux-mali-attach.sh>) | `tools/termux-mali-attach.sh` | 8.5 KB |
| [termux-mali-dep-loop.sh](<doc/手机部署/tools/termux-mali-dep-loop.sh>) | `tools/termux-mali-dep-loop.sh` | 5.7 KB |
| [termux-mali-origin-fix.sh](<doc/手机部署/tools/termux-mali-origin-fix.sh>) | `tools/termux-mali-origin-fix.sh` | 5.6 KB |
| [termux-nnapi-abi-probe.sh](<doc/手机部署/tools/termux-nnapi-abi-probe.sh>) | `tools/termux-nnapi-abi-probe.sh` | 5.3 KB |
| [termux-nnapi-enum.sh](<doc/手机部署/tools/termux-nnapi-enum.sh>) | `tools/termux-nnapi-enum.sh` | 6.2 KB |
| [termux-nnapi-enum2.sh](<doc/手机部署/tools/termux-nnapi-enum2.sh>) | `tools/termux-nnapi-enum2.sh` | 5.7 KB |
| [termux-nnapi-runtime-check.sh](<doc/手机部署/tools/termux-nnapi-runtime-check.sh>) | `tools/termux-nnapi-runtime-check.sh` | 8.6 KB |
| [termux-npu-e2e.sh](<doc/手机部署/tools/termux-npu-e2e.sh>) | `tools/termux-npu-e2e.sh` | 12.0 KB |
| [termux-npu-tflite.sh](<doc/手机部署/tools/termux-npu-tflite.sh>) | `tools/termux-npu-tflite.sh` | 6.4 KB |
| [termux-perf-detail.sh](<doc/手机部署/tools/termux-perf-detail.sh>) | `tools/termux-perf-detail.sh` | 5.5 KB |
| [termux-perf-fill.sh](<doc/手机部署/tools/termux-perf-fill.sh>) | `tools/termux-perf-fill.sh` | 2.7 KB |
| [termux-perf-lean.sh](<doc/手机部署/tools/termux-perf-lean.sh>) | `tools/termux-perf-lean.sh` | 3.7 KB |
| [termux-probe-model-sources.sh](<doc/手机部署/tools/termux-probe-model-sources.sh>) | `tools/termux-probe-model-sources.sh` | 4.6 KB |
| [termux-run.sh](<doc/手机部署/tools/termux-run.sh>) | `tools/termux-run.sh` | 2.2 KB |
| [termux-system-vulkan-test.sh](<doc/手机部署/tools/termux-system-vulkan-test.sh>) | `tools/termux-system-vulkan-test.sh` | 5.8 KB |
| [termux-test-qwen35.sh](<doc/手机部署/tools/termux-test-qwen35.sh>) | `tools/termux-test-qwen35.sh` | 3.8 KB |
| [termux-verify-models.sh](<doc/手机部署/tools/termux-verify-models.sh>) | `tools/termux-verify-models.sh` | 3.1 KB |
| [termux-verify-ui.sh](<doc/手机部署/tools/termux-verify-ui.sh>) | `tools/termux-verify-ui.sh` | 3.9 KB |
| [termux-vulkan-android-loader.sh](<doc/手机部署/tools/termux-vulkan-android-loader.sh>) | `tools/termux-vulkan-android-loader.sh` | 5.7 KB |
| [交接文档.md](<doc/手机部署/交接文档.md>) | `交接文档.md` | 9.2 KB |
| [四模型架构与性能对比.md](<doc/手机部署/四模型架构与性能对比.md>) | `四模型架构与性能对比.md` | 14.4 KB |

## 树莓派（1）

| 文件 | 原路径 | 大小 |
| --- | --- | --- |
| [flash-sd.ps1](<doc/树莓派/flash-sd.ps1>) | `flash-sd.ps1` | 1.2 KB |
