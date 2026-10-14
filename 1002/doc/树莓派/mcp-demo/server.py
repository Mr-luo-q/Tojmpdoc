"""演示用的最小 MCP 服务器，用于验证 Home Assistant 的「外接 MCP」功能。

在 HA 的容器镜像里运行（该镜像自带 mcp SDK，无需额外安装）：

    docker run -d --name mcp-demo --network=host \
      --entrypoint python \
      -v /home/pi/mcp-demo:/app -w /app \
      ghcr.io/home-assistant/home-assistant:stable /app/server.py

MCP 端点：http://<主机>:8765/mcp
"""

import os
import platform
import socket
from datetime import datetime

from mcp.server.fastmcp import FastMCP

HOST = os.environ.get("MCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("MCP_PORT", "8765"))

mcp = FastMCP("raspberry-pi-demo", host=HOST, port=PORT)


@mcp.tool()
def get_server_time() -> str:
    """返回树莓派当前的日期和时间。"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


@mcp.tool()
def get_system_info() -> dict:
    """返回树莓派的系统信息（主机名、平台、Python 版本）。"""
    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python": platform.python_version(),
    }


@mcp.tool()
def echo(text: str) -> str:
    """把传入的文本原样返回，用于连通性测试。"""
    return f"echo: {text}"


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
