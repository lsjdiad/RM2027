#!/usr/bin/env python3
"""塌缩双嵌套链接 [[`X:n`](A)](A) → [`X:n`](A)。DRY=1 干跑。"""
import re, os, glob, sys
DRY = os.environ.get("DRY") == "1"
pat = re.compile(r'\[\[`([^`]+?)`\]\(([^)\s]+)\)\]\(([^)\s]+)\)')
n = 0; files = set()
for f in glob.glob("**/*.md", recursive=True):
    s0 = open(f, encoding='utf-8').read()
    def rep(m):
        global n
        lbl, a, b = m.group(1), m.group(2), m.group(3)
        n += 1
        if a != b:                       # 目标不同就不动（保守）
            return m.group(0)
        return f"[`{lbl}`]({a})"
    s1 = pat.sub(rep, s0)
    if s1 != s0:
        files.add(f)
        if not DRY:
            with open(f, 'w', encoding='utf-8') as fh: fh.write(s1)
print(f"{'【干跑】' if DRY else '✅ '}塌缩 {n} 处，涉及 {len(files)} 篇")
