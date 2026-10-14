#!/usr/bin/env python3
"""code-twin 全量自审：找"能被挑刺"的地方。"""
import re, os, glob, sys, collections, urllib.parse

ROOT = "/mnt/h/AI/shared/projects/competition/rm2027-drone/work/px4-code-twin"
PX4 = open(os.path.join(ROOT, "tools/source-root.conf"), encoding='utf-8').read()
PX4 = [l.strip() for l in PX4.split("\n") if l.strip() and not l.startswith("#")][0]
os.chdir(ROOT)

issues = collections.defaultdict(list)

# ── A1. 行号全量验证：(源文件, 行) 是否存在且行号在范围内 ──
CITE = re.compile(r'`((?:[A-Za-z0-9_./\-]+/)?[A-Za-z0-9_\-]+\.(?:c|cpp|h|hpp|md|yaml|cmake|txt|py|ld|mk|px4board|defconfig|json|in|sh)|Makefile|Kconfig|Dockerfile)[:#](\d+)')
ANCH = re.compile(r'^### `(.+?)`\s*$', re.M)
TAG  = re.compile(r'^\*\*↓ 文档在讲这里：\*\*\[`([^`]+?):(\d+)`\]', re.M)
n_cited = 0
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    if "## 标注源码" not in s: continue
    for m in TAG.finditer(s.split("## 标注源码",1)[1]):
        rel, ln = m.group(1), int(m.group(2)); n_cited += 1
        p = os.path.join(PX4, rel)
        if not os.path.exists(p): issues["A1 标注源文件不存在"].append(f"{f}: {rel}"); continue
        n = sum(1 for _ in open(p, encoding='utf-8', errors='replace'))
        if ln < 1 or ln > n: issues["A1 行号越界"].append(f"{f}: {rel}:{ln} (文件共 {n} 行)")

# ── A2. 站内跳转可达性（目标文件 + 锚点都存在）──
n_jump = 0
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    for m in re.finditer(r'\]\(([^)#\s]+\.md)#(src-[^)\s]+)\)', s):
        tgt = os.path.normpath(os.path.join(os.path.dirname(f) or ".", m.group(1))); n_jump += 1
        if not os.path.exists(tgt): issues["A2 跳转目标文件不存在"].append(f"{f} → {m.group(1)}"); continue
        if f'id="{m.group(2)}"' not in open(tgt, encoding='utf-8').read():
            issues["A2 锚点不存在"].append(f"{f} → {m.group(1)}#{m.group(2)}")
    # 普通 md 链接
    for m in re.finditer(r'\]\(([^)#\s]+\.md)(?:#[^)\s]*)?\)', s):
        if m.group(1).startswith(("http", "file:")): continue
        tgt = os.path.normpath(os.path.join(os.path.dirname(f) or ".", m.group(1)))
        if not os.path.exists(tgt): issues["A2 文档链接失效"].append(f"{f} → {m.group(1)}")
    for m in re.finditer(r'\]\(([^)\s]+\.(?:png|jpg|pdf|txt))\)', s):
        tgt = os.path.normpath(os.path.join(os.path.dirname(f) or ".", m.group(1)))
        if not os.path.exists(tgt): issues["A2 资源链接失效"].append(f"{f} → {m.group(1)}")

# ── A3. 机器路径残留 ──
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    for pat, name in ((r'file:///home/', "file:///home"), (r'/home/xien', "裸 /home/xien")):
        if re.search(pat, s) and not f.startswith("tools/"):
            issues["A3 机器路径残留"].append(f"{f}: {name}")

# ── B1. 结构：每篇该有的小节 ──
for f in sorted(glob.glob("**/*.md", recursive=True)):
    if f == "README.md" or f.startswith("tools/"): continue
    s = open(f, encoding='utf-8').read()
    if not re.search(r"^##+ *\d*\.? *跳转", s, re.M):
        issues["B1 缺「跳转」小节"].append(f)
    if len(s.split("\n")) < 30: issues["B1 过短（<30 行）"].append(f"{f} ({len(s.splitlines())} 行)")

# ── B2. 重复：「源码附录」与「标注源码」并存 ──
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    if "## 源码附录" in s and "## 标注源码" in s:
        issues["B2 两套代码段并存"].append(f)

# ── C1. README 与实际是否一致 ──
s = open("README.md", encoding='utf-8').read()
for layer in ("01_extracted", "02_code_twin", "03_moc", "04_notes"):
    real = len(glob.glob(f"{layer}/**/*.md", recursive=True))
    if f"{layer}/" not in s: issues["C1 README 未提到该层"].append(layer)

# ── C2. 源码根引用是否统一（应只指向 tools/source-root.conf）──
for f in glob.glob("**/*.md", recursive=True):
    if f.startswith("tools/"): continue
    s = open(f, encoding='utf-8').read()
    if "PX4-Autopilot" in s and "source-root.conf" not in s and "PX4-Autopilot" in s:
        issues["C2 提了源码根但没指向 conf"].append(f)

# ── D1. 未验证断言的信号词 ──
for f in glob.glob("**/*.md", recursive=True):
    s = open(f, encoding='utf-8').read()
    for pat in (r'我觉得', r'应该是吧', r'可能吧'):
        if re.search(pat, s): issues["D1 含糊措辞"].append(f"{f}: {pat}")

print("=" * 72)
print(f"审计范围: {len(glob.glob('**/*.md', recursive=True))} 篇")
print(f"标注源码条目: {n_cited}   站内跳转: {n_jump}")
print("=" * 72)
if not issues:
    print("✅ 没有发现问题")
else:
    for k in sorted(issues):
        v = issues[k]
        print(f"\n⚠️ [{k}]  {len(v)} 处")
        for x in v[:8]: print(f"     {x}")
        if len(v) > 8: print(f"     ... 还有 {len(v)-8} 处")
