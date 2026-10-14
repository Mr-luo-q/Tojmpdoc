r"""树莓派那台 HA 的接口小工具：登录 + REST + WebSocket 三种调用方式。

存在的理由：树莓派上的 HA（HA Container）用的账号和本机沙盒那台不一样，
本机的 HA 工具都指向沙盒、令牌也绑在那边，够不到树莓派。
这个脚本用账号密码换 access_token，并把 REST 与 WebSocket 两条通道暴露出来。

用法示例：
    python _work\pi\ha_api.py --base http://192.168.137.2:8123 --user pi --password ****** entries
    python _work\pi\ha_api.py ... entries bluetooth
    python _work\pi\ha_api.py ... get /api/config
    python _work\pi\ha_api.py ... post /api/config/config_entries/flow '{"handler":"bluetooth"}'
    python _work\pi\ha_api.py ... ws config_entries/get '{"domain":"bluetooth"}'
"""

import argparse
import json

import requests
import websocket


def login(base: str, user: str, password: str) -> str:
    """走 HA 的登录流程换一个 access_token：建流程 → 交账号密码 → 拿 code → 换 token。"""

    client_id = base + "/"
    flow = requests.post(
        f"{base}/auth/login_flow",
        json={"client_id": client_id, "handler": ["homeassistant", None], "redirect_uri": client_id},
        timeout=30,
    )
    flow.raise_for_status()
    flow_id = flow.json()["flow_id"]

    step = requests.post(
        f"{base}/auth/login_flow/{flow_id}",
        json={"client_id": client_id, "username": user, "password": password},
        timeout=30,
    )
    step.raise_for_status()
    payload = step.json()
    if payload.get("type") != "create_entry":
        raise SystemExit(f"登录失败：{json.dumps(payload.get('errors'), ensure_ascii=False)}")

    token = requests.post(
        f"{base}/auth/token",
        data={"grant_type": "authorization_code", "code": payload["result"], "client_id": client_id},
        timeout=30,
    )
    token.raise_for_status()
    return token.json()["access_token"]


def rest(base: str, token: str, method: str, path: str, body=None):
    """打一条 REST 请求；路径写成 /api/... 的形式，直接拼在 base 后面。"""

    response = requests.request(
        method.upper(),
        base + path,
        headers={"Authorization": f"Bearer {token}"},
        json=body,
        timeout=60,
    )
    return response.status_code, response.text


def ws_command(base: str, token: str, message: dict, wait: int = 1):
    """连 /api/websocket，认证后发一条命令，收 wait 条回执（默认 1 条）。"""

    url = base.replace("https://", "wss://").replace("http://", "ws://") + "/api/websocket"
    connection = websocket.create_connection(url, timeout=30)
    try:
        connection.recv()
        connection.send(json.dumps({"type": "auth", "access_token": token}))
        greeting = json.loads(connection.recv())
        if greeting.get("type") != "auth_ok":
            raise SystemExit(f"WebSocket 认证失败：{greeting}")
        connection.send(json.dumps(message, ensure_ascii=False))
        return [connection.recv() for _ in range(wait)]
    finally:
        connection.close()


def main() -> int:
    """解析参数，把一次调用打出去；结果原样打印，JSON 会整理成可读形式。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://192.168.137.2:8123", help="HA 地址（默认网线直连的树莓派）")
    parser.add_argument("--user", default="pi")
    parser.add_argument("--password", default="<HA登录口令已脱敏>")
    parser.add_argument("action", choices=["entries", "get", "post", "delete", "ws"])
    parser.add_argument("args", nargs="*")
    options = parser.parse_args()

    token = login(options.base, options.user, options.password)

    if options.action == "entries":
        path = "/api/config/config_entries/entry"
        if options.args:
            path += f"?domain={options.args[0]}"
        code, text = rest(options.base, token, "get", path)
        try:
            items = json.loads(text)
        except json.JSONDecodeError:
            print(f"[{code}] {text}")
            return 1
        print(f"[{code}] {len(items)} 个条目")
        for item in items:
            print(f"  {str(item.get('domain')):24} {str(item.get('state')):12} "
                  f"title={item.get('title')} disabled_by={item.get('disabled_by')}")
        return 0 if code == 200 else 1

    if options.action == "ws":
        message = json.loads(options.args[1]) if len(options.args) > 1 else {}
        message["id"] = 1
        message["type"] = options.args[0]
        for raw in ws_command(options.base, token, message):
            print(raw)
        return 0

    path = options.args[0]
    body = json.loads(options.args[1]) if len(options.args) > 1 else None
    code, text = rest(options.base, token, options.action, path, body)
    print(f"[{code}] {text[:4000]}")
    return 0 if code < 400 else 1


if __name__ == "__main__":
    raise SystemExit(main())
