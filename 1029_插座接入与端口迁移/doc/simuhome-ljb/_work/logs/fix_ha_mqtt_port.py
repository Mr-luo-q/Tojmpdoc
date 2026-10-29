"""把 HA 的 MQTT 集成端口从 1883 改到 2883（先停容器再改，避免写坏）。"""
import json
import shutil
from pathlib import Path

PATH = Path(r"D:\homeassistant-sandbox\.storage\core.config_entries")
raw = PATH.read_text(encoding="utf-8")
data = json.loads(raw)

changed = []
for entry in data["data"]["entries"]:
    if entry.get("domain") == "mqtt":
        before = dict(entry["data"])
        entry["data"]["port"] = 2883
        changed.append((entry["entry_id"], before, dict(entry["data"])))

if not changed:
    raise SystemExit("没有找到 mqtt 条目")

shutil.copy2(PATH, PATH.with_suffix(".bak"))
PATH.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
for entry_id, before, after in changed:
    print(entry_id, before, "->", after)
