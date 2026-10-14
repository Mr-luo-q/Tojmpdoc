r"""给沙盒 HA 做初始化，并签发长期访问令牌。全程走 API，不需要打开浏览器。

步骤：
  1. 首次运行：POST /api/onboarding/users 建 owner 账号（用户名/密码自动生成）
     已有凭据文件：走 /auth/login_flow 登录
  2. POST /auth/token 用授权码换 access_token
  3. 收尾引导（core_config / analytics / integration），失败不影响主流程
  4. WebSocket 调 auth/long_lived_access_token 签发长期令牌

产物（都在仓库的 _secrets\，该目录被 .gitignore 排除）：
  _secrets\ha_token.txt                 长期令牌，仓库脚本默认读这个路径
  _secrets\ha_sandbox_credentials.txt   沙盒 HA 的登录用户名/密码（各一行）

用法：python _work\ha\onboard.py
"""

import asyncio
import json
import secrets
import string
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import websockets

BASE = "http://127.0.0.1:8123"
WS_URL = "ws://127.0.0.1:8123/api/websocket"
CLIENT_ID = "http://simuhome-sandbox.local/"
USERNAME = "sandbox"

ROOT = Path(__file__).resolve().parents[2]
SECRETS = ROOT / "_secrets"
CRED_FILE = SECRETS / "ha_sandbox_credentials.txt"
TOKEN_FILE = SECRETS / "ha_token.txt"


def post_json(path: str, payload: dict, token: str | None = None) -> dict:
    """POST 一段 JSON，返回解析后的响应体。"""

    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read().decode("utf-8")
    return json.loads(body) if body else {}


def post_form(path: str, fields: dict) -> dict:
    """POST 表单，返回解析后的响应体。"""

    request = urllib.request.Request(
        BASE + path, data=urllib.parse.urlencode(fields).encode("utf-8"), method="POST"
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def get_auth_code() -> str:
    """建号或登录，拿到授权码。"""

    SECRETS.mkdir(exist_ok=True)
    if CRED_FILE.exists():
        username, password = CRED_FILE.read_text(encoding="utf-8").split()
        print(f"凭据文件已存在，改用登录流程：{username}")
        flow = post_json(
            "/auth/login_flow",
            {"client_id": CLIENT_ID, "handler": ["homeassistant", None], "redirect_uri": CLIENT_ID},
        )
        result = post_json(
            f"/auth/login_flow/{flow['flow_id']}",
            {"client_id": CLIENT_ID, "username": username, "password": password},
        )
        return result["result"]

    password = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(24))
    result = post_json(
        "/api/onboarding/users",
        {
            "client_id": CLIENT_ID,
            "name": "Sandbox",
            "username": USERNAME,
            "password": password,
            "language": "zh-Hans",
        },
    )
    CRED_FILE.write_text(f"{USERNAME}\n{password}\n", encoding="utf-8")
    print(f"已建沙盒 HA 账号：{USERNAME}（密码写入 {CRED_FILE.name}）")
    return result["auth_code"]


def finish_onboarding(access_token: str) -> None:
    """把引导剩下的几步走完，失败只提示不中断。"""

    for path, payload in (
        ("/api/onboarding/core_config", {"client_id": CLIENT_ID}),
        ("/api/onboarding/analytics", {}),
        ("/api/onboarding/integration", {"client_id": CLIENT_ID}),
    ):
        try:
            post_json(path, payload, token=access_token)
            print(f"引导步骤完成：{path}")
        except urllib.error.HTTPError as error:
            print(f"引导步骤跳过：{path} -> HTTP {error.code}")


async def create_long_lived_token(access_token: str) -> str:
    """走 WebSocket 命令签发长期令牌。"""

    async with websockets.connect(WS_URL, max_size=None) as socket:
        assert json.loads(await socket.recv())["type"] == "auth_required"
        await socket.send(json.dumps({"type": "auth", "access_token": access_token}))
        assert json.loads(await socket.recv())["type"] == "auth_ok"
        await socket.send(
            json.dumps(
                {
                    "id": 1,
                    "type": "auth/long_lived_access_token",
                    "client_name": "simuhome-sandbox",
                    "lifespan": 3650,
                }
            )
        )
        while True:
            message = json.loads(await socket.recv())
            if message.get("id") == 1:
                if not message.get("success"):
                    raise RuntimeError(f"签发长期令牌失败：{message}")
                return message["result"]


def main() -> None:
    auth_code = get_auth_code()
    access_token = post_form(
        "/auth/token",
        {"grant_type": "authorization_code", "code": auth_code, "client_id": CLIENT_ID},
    )["access_token"]
    finish_onboarding(access_token)
    token = asyncio.run(create_long_lived_token(access_token))
    TOKEN_FILE.write_text(token + "\n", encoding="utf-8")
    print(f"长期令牌已写入 {TOKEN_FILE}")


if __name__ == "__main__":
    main()
