"""确认 1883 与 18830 哪个能绑定。"""
import socket


def test(port):
    """尝试绑定并监听，返回是否成功。"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.bind(("127.0.0.1", port))
        sock.listen(1)
        return "可绑定"
    except Exception as exc:
        return f"失败 {type(exc).__name__} {exc}"
    finally:
        sock.close()


for port in (1883, 18830, 2883, 18883):
    print(f"{port}: {test(port)}")
