"""读源码根 —— 所有工具共用，禁止在别处硬编码路径。"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(HERE, "source-root.conf")

def source_root():
    if os.path.exists(CONF):
        for ln in open(CONF, encoding='utf-8'):
            ln = ln.strip()
            if ln and not ln.startswith('#'):
                return ln
    # 兜底：环境变量（便于 CI / 别的机器临时覆盖）
    return os.environ.get("PX4_SRC_ROOT", "")
