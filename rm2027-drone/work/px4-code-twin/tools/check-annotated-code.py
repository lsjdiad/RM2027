#!/usr/bin/env python3
"""A4：全量比对「标注源码」里贴的代码行 vs 源码原文（逐字）。"""
import re, os, glob, collections
ROOT = "/mnt/h/AI/shared/projects/competition/rm2027-drone/work/px4-code-twin"
PX4 = [l.strip() for l in open(os.path.join(ROOT,"tools/source-root.conf"),encoding='utf-8') if l.strip() and not l.startswith("#")][0]
os.chdir(ROOT)
bad = []; n = 0; sections = 0
for f in sorted(glob.glob("**/*.md", recursive=True)):
    s = open(f, encoding='utf-8').read()
    if "## 标注源码" not in s: continue
    sections += 1
    cur = None
    for ln in s.split("## 标注源码",1)[1].split("\n"):
        m = re.match(r'^### `(.+?)`', ln)
        if m: cur = m.group(1); continue
        m2 = re.match(r'^▶\s*(\d+) │ (.*)$', ln)
        if m2 and cur:
            num, shown = int(m2.group(1)), m2.group(2)
            p = os.path.join(PX4, cur)
            if not os.path.exists(p): bad.append((f, cur, num, "文件不存在")); continue
            try: real = open(p, encoding='utf-8', errors='replace').read().split("\n")[num-1]
            except Exception as e: bad.append((f, cur, num, str(e))); continue
            n += 1
            if shown.rstrip() != real.rstrip():
                bad.append((f, cur, num, f"文档[{shown[:40]}] ≠ 源码[{real[:40]}]"))
print(f"检查 {sections} 篇 / {n} 条 ▶ 标注行")
print(f"❌ 不一致 {len(bad)} 条")
for b in bad[:10]: print("   ", b)
