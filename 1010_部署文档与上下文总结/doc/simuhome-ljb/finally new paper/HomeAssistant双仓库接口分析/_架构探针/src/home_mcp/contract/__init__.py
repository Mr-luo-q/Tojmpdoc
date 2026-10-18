"""契约层：与后端无关的工具定义与判定规则，只依赖标准库。"""

from dataclasses import dataclass
from typing import Any, Callable


@dataclass(frozen=True)
class ToolSpec:
    """一个工具对外的契约：名字、参数、返回。"""

    name: str
    params: dict[str, str]
    returns: str


TOOLS: tuple[ToolSpec, ...] = (
    ToolSpec("observe_home", {}, "房间与环境的快照"),
    ToolSpec("execute_action", {"device_id": "str", "action": "str"}, "执行结果"),
    ToolSpec("memory", {"op": "read 或 write", "key": "str"}, "记忆内容"),
)


def missing_tools(implemented: dict[str, Any]) -> list[str]:
    """返回契约里有、后端却没有实现的工具名。"""

    return sorted({t.name for t in TOOLS} - set(implemented))


def extra_tools(implemented: dict[str, Any]) -> list[str]:
    """返回后端实现了、契约里却没有的工具名。"""

    return sorted(set(implemented) - {t.name for t in TOOLS})


def evaluate_condition(actual: Any, op: str, expected: Any) -> bool:
    """目标条件求值：支持 lt、lte、gt、gte、eq、ne 六种操作符。"""

    table: dict[str, Callable[[Any, Any], bool]] = {
        "lt": lambda a, b: a < b,
        "lte": lambda a, b: a <= b,
        "gt": lambda a, b: a > b,
        "gte": lambda a, b: a >= b,
        "eq": lambda a, b: a == b,
        "ne": lambda a, b: a != b,
    }
    if op not in table:
        raise ValueError(f"不支持的操作符：{op}")
    return table[op](actual, expected)
