"""运行时基础设施：配置加载，只依赖标准库与 PyYAML。"""

from pathlib import Path
import os
import re

import yaml


_PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


def substitute(text: str, env: dict[str, str] | None = None) -> str:
    """把 ${VAR} 占位符替换成环境变量的值，缺失时替换为空串。"""

    source = env if env is not None else os.environ
    return _PLACEHOLDER.sub(lambda m: source.get(m.group(1), ""), text)


def load_config(path: str | Path) -> dict:
    """读取配置：先做占位符替换，再交给 YAML 解析。"""

    raw = Path(path).read_text(encoding="utf-8")
    return yaml.safe_load(substitute(raw)) or {}
