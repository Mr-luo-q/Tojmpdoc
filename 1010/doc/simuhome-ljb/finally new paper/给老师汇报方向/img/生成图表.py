"""生成汇报用图表：GRPO 单卡显存边界曲线、GRPO 正式训练结果对比。

输入数据均来自同级目录的《边界扫描结果.md》，不读外部文件。
输出两张 PNG，直接插在汇报文档里。
"""

import os

import matplotlib
import matplotlib.pyplot as plt

# 用微软雅黑渲染中文，避免图中出现方块
matplotlib.rcParams["font.sans-serif"] = ["Microsoft YaHei"]
matplotlib.rcParams["axes.unicode_minus"] = False

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# 边界扫描原始数据：(标签, batch, num_generation, max_completion, 峰值显存GB, 步时秒)
BOUNDARY = [
    ("基准", 2, 4, 256, 22.7, 22),
    ("s1", 4, 4, 256, 24.2, 23),
    ("s2", 4, 8, 256, 25.0, 24),
    ("s3", 4, 8, 512, 29.0, 45),
    ("s4", 8, 8, 512, 35.8, 88),
    ("s5", 8, 16, 512, 43.8, 55),
    ("s6", 8, 16, 1024, 91.1, 136),
]


def figure_memory_boundary() -> str:
    """画峰值显存随 rollout 规模变化的曲线，标出 96GB 物理上限。"""
    tokens = [b * g * m for _, b, g, m, _, _ in BOUNDARY]
    memory = [mem for *_, mem, _ in BOUNDARY]
    step_time = [t for *_, t in BOUNDARY]
    labels = [f"{name}\n{b}×{g}×{m}" for name, b, g, m, _, _ in BOUNDARY]

    fig, ax = plt.subplots(figsize=(9, 5.2), dpi=160)
    ax.plot(tokens, memory, "o-", color="#1f6fb4", linewidth=2, markersize=7)
    ax.axhline(96, color="#c0392b", linestyle="--", linewidth=1.5)
    ax.text(tokens[0], 96.8, "单卡物理上限 96 GB", color="#c0392b", fontsize=10)

    for x, y, name, t in zip(tokens, memory, labels, step_time):
        ax.annotate(name, (x, y), textcoords="offset points", xytext=(0, 10),
                    ha="center", fontsize=9)
        ax.annotate(f"{t}s/step", (x, y), textcoords="offset points", xytext=(0, -20),
                    ha="center", fontsize=8, color="#555555")

    ax.set_xscale("log", base=2)
    ax.set_xlabel("每步最大 completion token 数（batch × num_gen × max_comp）", fontsize=11)
    ax.set_ylabel("GPU 峰值显存 (GB)", fontsize=11)
    ax.set_title("Qwen3-4B + LoRA(rank32) + GRPO：单卡 96GB 显存边界实测", fontsize=13)
    ax.grid(alpha=0.3, which="both")
    ax.set_ylim(0, 105)

    path = os.path.join(OUT_DIR, "grpo_memory_boundary.png")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return path


def figure_training_summary() -> str:
    """画 250 步正式训练的 reward 前后对比，并把 KL / 显存等指标标在图上。"""
    fig, ax = plt.subplots(figsize=(7.2, 4.6), dpi=160)
    names = ["前 20 步平均", "后 20 步平均"]
    values = [-1.04, -0.47]
    bars = ax.bar(names, values, color=["#8fbcd4", "#1f6fb4"], width=0.5)
    for bar, v in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, v - 0.08, f"{v:.2f}",
                ha="center", va="top", fontsize=12, color="#1b3b53")

    ax.annotate("", xy=(1, -0.47), xytext=(0, -1.04),
                arrowprops=dict(arrowstyle="->", color="#c0392b", linewidth=2))
    ax.text(0.5, -0.66, "reward +0.57", color="#c0392b", ha="center", fontsize=12)

    ax.set_ylim(-1.3, 0.15)
    ax.axhline(0, color="#999999", linewidth=1)
    ax.set_ylabel("平均 reward", fontsize=11)
    ax.set_title("Qwen3-4B LoRA + GRPO 正式训练 250 步", fontsize=13)
    ax.text(0.99, 0.03,
            "KL: 0 → 0.02\n峰值显存 22.7 GB（均值 22.0 GB）\nGPU 峰值利用率 88%",
            transform=ax.transAxes, ha="right", va="bottom", fontsize=10,
            bbox=dict(boxstyle="round", facecolor="#f2f6fa", edgecolor="#c8d6e2"))
    ax.grid(axis="y", alpha=0.3)

    path = os.path.join(OUT_DIR, "grpo_training_summary.png")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return path


if __name__ == "__main__":
    for p in (figure_memory_boundary(), figure_training_summary()):
        print("saved:", p)
