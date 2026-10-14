r"""通过 config flow API 给沙盒 HA 添加 MQTT 集成（不用打开浏览器）。

HA 的 MQTT 集成只能走 config flow（YAML 配置早就取消了），这里用 REST 版的
config flow 接口逐步提交：起一个 mqtt flow，按返回的 data_schema 逐字段填值，
跟着步骤走直到 create_entry。

鉴权用 _secrets\ha_token.txt。broker 地址填 host.docker.internal:1883：
HA 在容器里，经 host.docker.internal 访问宿主回环（见 deploy\03 的说明）。

用法：python _work\ha\add_mqtt.py
"""

import json
import urllib.error
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8123"
ROOT = Path(__file__).resolve().parents[2]
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()

VALUES = {
    "broker": "host.docker.internal",
    "port": 1883,
    "username": "",
    "password": "",
    "discovery": True,
    "discovery_prefix": "homeassistant",
    "client_id": "",
    "keepalive": 60,
    "certificate": "auto",
    "tls": False,
    "verify_ssl": True,
}


def call(path: str, payload: dict | None = None) -> dict:
    """POST 一段 JSON，带长期令牌。"""

    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload or {}).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {TOKEN}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{path} -> HTTP {error.code}: {error.read().decode('utf-8')}") from None
    return json.loads(body) if body else {}


def field_names(schema: object) -> list[str]:
    """从 config flow 返回的 data_schema 里取出字段名。"""

    if isinstance(schema, list):
        return [item["name"] for item in schema if isinstance(item, dict) and "name" in item]
    if isinstance(schema, dict):
        properties = schema.get("properties")
        if isinstance(properties, dict):
            return list(properties)
    return []


def main() -> None:
    flow = call("/api/config/config_entries/flow", {"handler": "mqtt"})
    for _ in range(6):
        step = flow.get("step_id")
        flow_type = flow.get("type")
        print(f"步骤：{step}（{flow_type}）")

        if flow_type == "create_entry":
            print(f"已创建集成：{flow.get('title')}")
            return

        names = field_names(flow.get("data_schema"))
        if not names:
            print("这一步没有可填字段，原样提交")
        payload = {name: VALUES[name] for name in names if name in VALUES}
        unknown = [name for name in names if name not in VALUES]
        if unknown:
            print(f"未知字段，脚本不认识：{unknown}")
        print(f"提交：{payload}")
        flow = call(f"/api/config/config_entries/flow/{flow['flow_id']}", payload)

    print(f"步数超出预期，停在：{json.dumps(flow, ensure_ascii=False)[:400]}")


if __name__ == "__main__":
    main()
