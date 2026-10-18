"""入口：读环境变量选后端，组装工具表。探针里不起真实 MCP 服务。"""

import importlib
import os

from .server import build_registry, list_tool_names


BACKENDS: dict[str, str] = {
    "ha": "home_mcp.backend_ha",
    "fake": "home_mcp.backend_fake",
}


def load_backend(name: str):
    """按名字加载后端模块，名字非法时抛错。"""

    if name not in BACKENDS:
        raise KeyError(f"未知后端：{name}，可选：{sorted(BACKENDS)}")
    return importlib.import_module(BACKENDS[name])


def main() -> dict:
    """组装并返回结果：工具名列表与后端名。"""

    backend_name = os.environ.get("HOME_MCP_BACKEND", "ha")
    backend = load_backend(backend_name)
    build_registry(backend.TOOLS)
    return {"backend": backend_name, "tools": list_tool_names()}
