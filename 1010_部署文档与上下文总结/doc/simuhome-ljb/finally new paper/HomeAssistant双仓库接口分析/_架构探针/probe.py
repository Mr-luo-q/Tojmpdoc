"""六个探针：实测这套架构的解耦程度，打印审查报告。"""

import ast
import hashlib
import importlib
import os
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
PKG = SRC / "home_mcp"
sys.path.insert(0, str(SRC))

SUB = ["entry", "server", "errors", "contract", "backend_ha", "backend_fake", "runtime"]
LEAK_WORDS = ["entity", "domain", "service", "rest", "ws", "sqlite", "ha_"]


def module_name(path: Path) -> str:
    """把文件路径换算成模块名，__init__.py 归到所在目录。"""

    rel = path.relative_to(SRC)
    parts = list(rel.parts[:-1])
    if path.stem != "__init__":
        parts.append(path.stem)
    return ".".join(parts)


def top(module: str) -> str | None:
    """取模块的二级名（home_mcp.contract.x → contract），不是本包则返回 None。"""

    parts = module.split(".")
    return parts[1] if len(parts) > 1 and parts[0] == "home_mcp" else None


def edges_of(path: Path) -> set[str]:
    """扫一个文件的 import，返回它依赖的本包二级模块集合。"""

    module = module_name(path)
    parent = module if path.stem == "__init__" else module.rsplit(".", 1)[0]
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            if node.level:
                base = parent.split(".")
                trimmed = base[: len(base) - (node.level - 1)] if node.level > 1 else base
                target = ".".join(trimmed + ([node.module] if node.module else []))
            else:
                target = node.module or ""
            name = top(target)
            if name and name != top(module):
                found.add(name)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                name = top(alias.name)
                if name and name != top(module):
                    found.add(name)
    return found


def hashes() -> dict[str, str]:
    """算整个包内所有文件的哈希，用于验证“换后端不改文件”。"""

    result = {}
    for path in sorted(PKG.rglob("*.py")):
        result[str(path.relative_to(PKG))] = hashlib.sha256(path.read_bytes()).hexdigest()[:12]
    return result


def p1_dependencies() -> tuple[bool, list[str]]:
    """P1：依赖方向是否单向、有没有环。"""

    graph: dict[str, set[str]] = {}
    for path in sorted(PKG.rglob("*.py")):
        name = top(module_name(path))
        if name:
            graph.setdefault(name, set()).update(edges_of(path))
    lines = []
    for name in SUB:
        deps = sorted(graph.get(name, set()))
        lines.append(f"  {name:14s} → {', '.join(deps) if deps else '(只依赖标准库)'}")
    ok, visiting, done = True, set(), set()

    def walk(node: str, stack: list[str]) -> None:
        nonlocal ok
        if node in done:
            return
        if node in visiting:
            lines.append(f"  ❌ 发现环：{' → '.join(stack + [node])}")
            ok = False
            return
        visiting.add(node)
        for dep in graph.get(node, set()):
            walk(dep, stack + [node])
        visiting.discard(node)
        done.add(node)

    for name in SUB:
        walk(name, [])
    return ok, lines


def p2_no_leak() -> tuple[bool, list[str]]:
    """P2：协议壳与契约层里不许出现后端词汇。"""

    lines, ok = [], True
    for rel in ["server.py", "entry.py", "contract/__init__.py"]:
        text = (PKG / rel).read_text(encoding="utf-8").lower()
        hits = [w for w in LEAK_WORDS if w in text]
        lines.append(f"  {rel:22s} 命中后端词汇：{hits if hits else '无'}")
        if hits:
            ok = False
    return ok, lines


def p3_swap_backend() -> tuple[bool, list[str]]:
    """P3：换后端只改环境变量，文件哈希与工具表不变。"""

    entry = importlib.import_module("home_mcp.entry")
    before = hashes()
    results = {}
    for name in ("ha", "fake"):
        os.environ["HOME_MCP_BACKEND"] = name
        importlib.reload(entry)
        results[name] = entry.main()
    after = hashes()
    same_files = before == after
    same_tools = results["ha"]["tools"] == results["fake"]["tools"]
    ha_backend = importlib.import_module("home_mcp.backend_ha")
    fake_backend = importlib.import_module("home_mcp.backend_fake")
    ha_rooms = ha_backend.observe_home()["rooms"]
    fake_rooms = fake_backend.observe_home()["rooms"]
    different_data = ha_rooms != fake_rooms
    lines = [
        f"  文件哈希前后一致：{same_files}",
        f"  两个后端的工具表一致：{same_tools} → {results['ha']['tools']}",
        f"  两个后端的数据不同：{different_data} → ha={ha_rooms}, fake={fake_rooms}",
    ]
    return same_files and same_tools and different_data, lines


def p4_fail_fast() -> tuple[bool, list[str]]:
    """P4：后端少实现工具时，启动期就要报错。"""

    server = importlib.import_module("home_mcp.server")
    errors = importlib.import_module("home_mcp.errors")
    try:
        server.build_registry({"observe_home": lambda: None})
    except errors.MissingToolsError as err:
        message = str(err)
        ok = "execute_action" in message and "memory" in message
        return ok, [f"  抛出 MissingToolsError：{message}", f"  报错信息含全部缺失项：{ok}"]
    return False, ["  ❌ 没有报错，契约形同虚设"]


def p5_contract_reuse() -> tuple[bool, list[str]]:
    """P5：同一套契约检查能在两个后端上复用。"""

    contract = importlib.import_module("home_mcp.contract")
    lines, ok = [], True
    for name in ("home_mcp.backend_ha", "home_mcp.backend_fake"):
        backend = importlib.import_module(name)
        missing = contract.missing_tools(backend.TOOLS)
        snapshot = backend.TOOLS["observe_home"]()
        executed = backend.TOOLS["execute_action"]("dev_1", "turn_on")
        good = not missing and "rooms" in snapshot and executed["device_id"] == "dev_1"
        lines.append(
            f"  {name:26s} 缺工具={missing or '无'}，快照含 rooms={('rooms' in snapshot)}，动作回执 ok={executed['device_id'] == 'dev_1'}"
        )
        ok = ok and good
    return ok, lines


def p6_config_placeholder() -> tuple[bool, list[str]]:
    """P6：配置能用 ${VAR}，且不依赖自定义 YAML tag。"""

    runtime = importlib.import_module("home_mcp.runtime")
    os.environ["PROBE_TOKEN"] = "tok_123"
    with tempfile.TemporaryDirectory() as tmp:
        cfg = Path(tmp) / "config.yaml"
        cfg.write_text(
            "ha:\n  base_url: http://localhost:8123\n  token: ${PROBE_TOKEN}\n",
            encoding="utf-8",
        )
        data = runtime.load_config(cfg)
    ok = data["ha"]["token"] == "tok_123"
    return ok, [
        f"  ${{PROBE_TOKEN}} 替换结果：{data['ha']['token']}",
        "  配置文件里不使用 !env 之类的自定义 tag（PyYAML 不认）",
    ]


def main() -> int:
    """依次跑六个探针，打印报告并返回退出码。"""

    probes = [
        ("P1 依赖方向与环检测", p1_dependencies),
        ("P2 协议壳与契约层无后端词汇", p2_no_leak),
        ("P3 换后端只改环境变量", p3_swap_backend),
        ("P4 契约强制（缺工具即报错）", p4_fail_fast),
        ("P5 契约检查可跨后端复用", p5_contract_reuse),
        ("P6 配置占位符 ${VAR}", p6_config_placeholder),
    ]
    failed = 0
    print("=" * 72)
    print("架构解耦审查报告")
    print("=" * 72)
    for title, fn in probes:
        try:
            ok, lines = fn()
        except Exception as err:  # noqa: BLE001
            ok, lines = False, [f"  探针异常：{type(err).__name__}: {err}"]
        print(f"\n[{ '通过' if ok else '不通过' }] {title}")
        for line in lines:
            print(line)
        failed += 0 if ok else 1
    print("\n" + "=" * 72)
    print(f"结论：{len(probes) - failed} / {len(probes)} 项通过")
    print("=" * 72)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
