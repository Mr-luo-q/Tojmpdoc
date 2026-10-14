"""HA 后端：把契约里的三个工具用 HA 的语义实现，探针里返回假数据。"""

from typing import Any


def observe_home() -> dict[str, Any]:
    """读全屋快照：真实实现会打 HA 的 /api/states。"""

    return {"rooms": ["living_room", "kitchen"], "source": "ha"}


def execute_action(device_id: str, action: str) -> dict[str, Any]:
    """执行设备动作：真实实现会调 HA 的 /api/services。"""

    return {"device_id": device_id, "action": action, "service": "switch.turn_on", "source": "ha"}


def memory(op: str, key: str) -> dict[str, Any]:
    """读写记忆：真实实现会写本地 sqlite。"""

    return {"op": op, "key": key, "value": None, "source": "ha"}


TOOLS = {"observe_home": observe_home, "execute_action": execute_action, "memory": memory}
