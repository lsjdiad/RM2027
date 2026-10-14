#!/usr/bin/env python3
"""一键换根：把 file://<旧根>/<相对路径>#L<n> 换成 file://<新根>/<相对路径>#L<n>。

★ 为什么不用"按 PX4-Autopilot 字符串切"：旧根若叫 /x/PX4-Autopilot-test，
  那个字符串会切错（把 -test 漏进相对路径）。本脚本改为【按已知顶层目录名截取】，
  与"旧根长什么样"完全无关。

用法：
    python3 tools/rebase-links.py --dry-run          # ★ 先干跑，只打印不写文件
    python3 tools/rebase-links.py                    # 用 conf 里的值重写全部链接
    python3 tools/rebase-links.py --set /path/to/PX4 # 改 conf 再重写
"""
import re, os, sys, glob, argparse
from urllib.parse import quote, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CONF = os.path.join(HERE, "source-root.conf")
sys.path.insert(0, HERE)
from _root import source_root

# PX4 仓库的顶层条目（相对路径必以其中之一开头）
TOP = ("platforms", "boards", "src", "ROMFS", "cmake", "msg", "build",
       "Tools", "docs", "nuttx-config", "test", "integrationtest", "launch")
TOP_FILE = ("Makefile", "CMakeLists.txt", "Kconfig", "Dockerfile", "README.md", ".px4board")

ap = argparse.ArgumentParser()
ap.add_argument("--set", help="新的源码根（写进 source-root.conf）")
ap.add_argument("--dry-run", action="store_true", help="只打印样例，不写文件")
a = ap.parse_args()

if a.set:
    t = open(CONF, encoding='utf-8').read()
    open(CONF, 'w', encoding='utf-8').write(re.sub(r'(?m)^(/.*)$', a.set, t, count=1))
    print(f"✅ conf ← {a.set}")

new = source_root()
if not new: sys.exit("❌ source-root.conf 里没有有效路径")

def rel_of(url_path):
    """从任意绝对路径里，截出相对 PX4 根的路径。认不出就返回 None（绝不猜）。"""
    p = unquote(url_path)
    for t in TOP:
        m = re.search(r'(?<=/)' + re.escape(t) + r'/', p)
        if m: return "/" + p[m.start():]
    for t in TOP_FILE:
        m = re.search(r'(?<=/)' + re.escape(t) + r'$', p)
        if m: return "/" + p[m.start():]
    return None

PAT = re.compile(r'file://([^)\s]+?)#L(\d+)')
stats = {"ok": 0, "skip": 0}
samples = []
for f in glob.glob(ROOT + "/**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    def rep(m):
        rel = rel_of(m.group(1))
        if rel is None:
            stats["skip"] += 1; return m.group(0)
        stats["ok"] += 1
        if len(samples) < 3:
            samples.append("file://" + quote(new, safe="/") + rel + "#L" + m.group(2))
        return "file://" + quote(new, safe="/") + rel + "#L" + m.group(2)
    s2 = PAT.sub(rep, s)
    if not a.dry_run and s2 != s:
        with open(f, 'w', encoding='utf-8') as fh: fh.write(s2)
print(("【干跑】" if a.dry_run else "✅ ") + f"可重写 {stats['ok']} 条，跳过 {stats['skip']} 条")
for x in samples: print("   样例:", x)
