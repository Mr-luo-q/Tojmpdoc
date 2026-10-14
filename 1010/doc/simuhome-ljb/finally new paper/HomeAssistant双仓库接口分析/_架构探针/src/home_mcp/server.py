"""协议壳：只认契约与注入的后端，不认识任何具体后端。"""

from typing import Any

from .contract import TOOLS, extra_tools, missing_tools
from .errors import MissingToolsError


def build_registry(backend_tools: dict[str, Any]) -> dict[str, Any]:
    """校验后端实现是否满足契约，返回按契约顺序排列的工具表。"""

    missing = missing_tools(backend_tools)
    if missing:
        raise MissingToolsError(f"后端缺少工具实现：{missing}")
    extra = extra_tools(backend_tools)
    if extra:
        raise MissingToolsError(f"后端实现了未定义的工具：{extra}")
    return {spec.name: backend_tools[spec.name] for spec in TOOLS}


def list_tool_names() -> list[str]:
    """按契约顺序返回工具名，供 tools/list 使用。"""

    return [spec.name for spec in TOOLS]
