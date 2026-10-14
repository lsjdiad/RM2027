#!/usr/bin/env python3
"""给「标注源码」的每条插 HTML 锚点，并把 file:// 链接重写成【站内相对链接】。

为什么这样做（用户提出的问题）:
  [`Makefile:237`](file:///home/xien/%E6%A1%8C%E9%9D%A2/.../Makefile#L237)
  ⇒ ① 带机器路径（换机器/给队友就废）② URL 又长又丑 ③ 违反"路径只维护在真源"
    ④ ★ 最根本：把你送到【源码树】，可那段代码【笔记里已经有了】
  改成 ⇒ [`Makefile:237`](../02_code_twin/build/Makefile.md#src-Makefile-237)
  ⇒ 相对路径 · 无机器名 · 短 · 而且【跳过去代码旁边就是文档的解释】

用法（流水线顺序）:
    python3 tools/link-sources.py .        # ① 行号 → 可点链接（暂时是 file://）
    python3 tools/annotate-sources.py .    # ② 生成「标注源码」（这一步产生代码）
    python3 tools/anchorize-sources.py .   # ③ ★ 插锚点 + 把 file:// 改写成站内跳转
DRY=1 python3 tools/anchorize-sources.py . # 干跑（只打印不改）
"""
import re, os, glob, sys, collections
from urllib.parse import unquote, quote
DRY = ("--dry-run" in sys.argv) or (os.environ.get("DRY") == "1")   # ★ 默认真写；--dry-run 才干跑

def sid(rel, line):
    s = re.sub(r'[^A-Za-z0-9]+', '-', rel).strip('-')
    return f"src-{s}-{line}"

# ① 建立 (源文件, 行) → (孪生篇, 锚点) 索引
index = {}
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    if "## 标注源码" not in s: continue
    sec = s.split("## 标注源码", 1)[1]
    cur = None
    for ln in sec.split("\n"):
        m = re.match(r'^### `(.+?)`', ln)
        if m: cur = m.group(1); continue
        m2 = re.match(r'^\*\*↓ 文档在讲这里：\*\*\[`([^`]+?):(\d+)`\]', ln)
        if m2 and cur:
            rel, num = cur, int(m2.group(2))
            index[(rel, num)] = (f, sid(rel, num))
print(f"索引: {len(index)} 条 (源文件,行) → 孪生篇锚点")

# ② 给标注源码的每条插锚点
n_anchor = 0
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    if "## 标注源码" not in s: continue
    head, sec = s.split("## 标注源码", 1)
    cur = None; out = []
    for ln in sec.split("\n"):
        m = re.match(r'^### `(.+?)`', ln)
        if m: cur = m.group(1)
        m2 = re.match(r'^\*\*↓ 文档在讲这里：\*\*\[`([^`]+?):(\d+)`\]', ln)
        if m2 and cur:
            out.append(f'<a id="{sid(cur, int(m2.group(2)))}"></a>')
            n_anchor += 1
        out.append(ln)
    ns = head + "## 标注源码" + "\n".join(out)
    if not DRY and ns != s:
        with open(f, 'w', encoding='utf-8') as fh: fh.write(ns)
print(f"{'【干跑】' if DRY else '✅ '}插锚点 {n_anchor} 个")

# ③ 重写 file:// 链接
LINK = re.compile(r'\[`([^`]+?):(\d+)`\]\(file://([^)#]+)#L(\d+)\)')
n_rew = n_miss = 0; miss = collections.Counter()
for f in glob.glob("**/*.md", recursive=True):
    s0 = open(f, encoding='utf-8').read()
    def rep(m):
        global n_rew, n_miss
        label, line, path = m.group(1), int(m.group(2)), unquote(m.group(3))
        j = path.find("PX4-Autopilot/")
        rel = path[j+len("PX4-Autopilot/"):] if j >= 0 else None
        hit = index.get((rel, line))
        if not hit:
            # ★ 解不掉 ⇒ 自动【降级为纯文本】，否则 link-sources 每次都会重新生成 file:// 外链，
            #   导致"流水线不幂等"。这条是实测踩出来的。
            n_miss += 1; miss[rel] += 1
            return f"`{m.group(1)}:{line}`"
        twin, anchor = hit
        relpath = os.path.relpath(twin, os.path.dirname(f) or ".")
        n_rew += 1
        return f"[`{label}:{line}`]({relpath}#{anchor})"
    s1 = LINK.sub(rep, s0)
    if not DRY and s1 != s0:
        with open(f, 'w', encoding='utf-8') as fh: fh.write(s1)
print(f"{'【干跑】' if DRY else '✅ '}重写链接 {n_rew} 条，未命中 {n_miss} 条")
if miss: print("  未命中源文件 top5:", miss.most_common(5))
