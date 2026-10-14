"""第二个后端：结构相同、数据来源不同，用来验证后端可替换。"""

from typing import Any


def observe_home() -> dict[str, Any]:
    """读全屋快照：换成内存里的固定数据。"""

    return {"rooms": ["room_a", "room_b", "room_c"], "source": "fake"}


def execute_action(device_id: str, action: str) -> dict[str, Any]:
    """执行设备动作：换成内存里模拟的服务名。"""

    return {"device_id": device_id, "action": action, "service": "fake.do", "source": "fake"}


def memory(op: str, key: str) -> dict[str, Any]:
    """读写记忆：换成内存字典。"""

    return {"op": op, "key": key, "value": "fake-value", "source": "fake"}


TOOLS = {"observe_home": observe_home, "execute_action": execute_action, "memory": memory}
