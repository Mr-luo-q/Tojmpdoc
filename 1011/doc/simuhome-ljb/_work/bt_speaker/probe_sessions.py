r"""列出本机音频会话里属于 python.exe 的项，用状态判断"还有没有在出声"。

Windows 的音频会话状态：0=Inactive（没在播）、1=Active（正在播）、2=Expired。
用法：python _work\bt_speaker\probe_sessions.py
"""

import sys

from pycaw.pycaw import AudioUtilities


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    found = 0
    for session in AudioUtilities.GetAllSessions():
        process = session.Process
        name = process.name() if process else "(system)"
        if name.lower() != "python.exe":
            continue
        found += 1
        state = "?"
        for attr in ("State", "state"):
            try:
                state = getattr(session, attr)
                break
            except Exception:  # noqa: BLE001
                continue
        label = {0: "Inactive", 1: "Active", 2: "Expired"}.get(state, str(state))
        print(f"  PID {process.pid}  {name}  state={label}")

    if not found:
        print("  没有 python.exe 的音频会话（说明没在出声）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
