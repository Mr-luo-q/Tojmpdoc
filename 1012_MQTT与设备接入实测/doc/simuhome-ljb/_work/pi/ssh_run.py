r"""在树莓派上跑一条命令（Windows 自带的 ssh 没法在命令行里给密码，所以用 paramiko）。

用法：
    python _work\pi\ssh_run.py "uname -a"
    python _work\pi\ssh_run.py "ip -4 addr show eth0" "cat /etc/resolv.conf"
    python _work\pi\ssh_run.py --host 192.168.137.50 "df -h /"

账号默认 pi / password（来自 D:\项目\树莓派\树莓派配置记录.md）；
若 _secrets\pi_account.txt 存在（两行：用户名、密码），优先用它。
"""

import argparse
import sys
from pathlib import Path

import paramiko

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
ACCOUNT_FILE = REPO_ROOT / "_secrets" / "pi_account.txt"


def load_account() -> tuple[str, str]:
    r"""读账号：_secrets\pi_account.txt 优先，否则用配置记录里的默认值。"""

    if ACCOUNT_FILE.exists():
        lines = [x.strip() for x in ACCOUNT_FILE.read_text(encoding="utf-8").splitlines() if x.strip()]
        if len(lines) >= 2:
            return lines[0], lines[1]
    return "pi", "password"


def run(client: paramiko.SSHClient, command: str) -> int:
    """跑一条命令并把输出打到本机 stdout；返回远端退出码。"""

    print(f"$ {command}")
    _stdin, stdout, stderr = client.exec_command(command, timeout=120)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if out:
        print(out.rstrip())
    if err:
        print("[stderr] " + err.rstrip())
    if code:
        print(f"[退出码 {code}]")
    return code


def run_sudo(client: paramiko.SSHClient, command: str, password: str) -> int:
    """用 sudo -S 跑一条命令：密码通过 stdin 喂进去，不出现在命令行里。"""

    print(f"$ sudo {command}")
    stdin, stdout, stderr = client.exec_command(f"sudo -S -p '' {command}", timeout=180)
    stdin.write(password + "\n")
    stdin.flush()
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if out:
        print(out.rstrip())
    if err:
        print("[stderr] " + err.rstrip())
    if code:
        print(f"[退出码 {code}]")
    return code


def put(client: paramiko.SSHClient, local: str, remote: str) -> None:
    """把一个本地文件传到远端（当前用的是覆盖式 SFTP）。"""

    with client.open_sftp() as sftp:
        sftp.put(local, remote)
    print(f"[上传] {local} -> {remote}")


def main() -> int:
    """连上去，先处理上传，再把命令行给的每条命令依次跑掉。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="192.168.137.50")
    parser.add_argument("--user")
    parser.add_argument("--password")
    parser.add_argument("--put", nargs=2, action="append", metavar=("LOCAL", "REMOTE"),
                        help="把本地文件传到远端，可以给多次")
    parser.add_argument("--sudo", action="store_true",
                        help="所有命令都用 sudo -S 跑（密码走 stdin，不落在命令行里）")
    parser.add_argument("commands", nargs="*")
    args = parser.parse_args()

    default_user, default_password = load_account()
    user = args.user or default_user
    password = args.password or default_password

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(args.host, username=user, password=password, timeout=15,
                       look_for_keys=False, allow_agent=False)
    except Exception as error:
        print(f"连不上 {user}@{args.host}：{type(error).__name__}: {error}", file=sys.stderr)
        return 2

    print(f"已登录 {user}@{args.host}\n")
    for local, remote in (args.put or []):
        try:
            put(client, local, remote)
        except Exception as error:
            print(f"[上传失败] {local}: {type(error).__name__}: {error}", file=sys.stderr)
            return 3
    if args.put and args.commands:
        print("")

    code = 0
    for command in args.commands:
        code = run_sudo(client, command, password) if args.sudo else run(client, command)
        print("")
    client.close()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
