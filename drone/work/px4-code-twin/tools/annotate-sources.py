
# ★★ 警告：本工具会【重建】「标注源码」段，因此会【冲掉】其中的 HTML 锚点。
#    跑完必须紧接着跑 anchorize-sources.py 把锚点补回来并重写链接！
#    正确顺序：link-sources.py → annotate-sources.py → anchorize-sources.py
#!/usr/bin/env python3
"""生成【标注源码】层：把文档里对每一行的解释，贴在源码那一行旁边。
输出 `## 标注源码（代码 + 本文档的解释）` 段落，取代原来只有代码的"源码附录"。"""
import re, os, sys, glob, collections
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _root import source_root   # ★ 源码根只在 tools/source-root.conf 维护
PX4 = source_root()
from urllib.parse import quote

LINK = re.compile(r'\[`([^`]+?):(\d+)`\]\(file://([^)#]+)#L(\d+)\)')
PLAIN = re.compile(r'`([A-Za-z0-9_./\-]+\.(?:c|cpp|h|hpp|txt|mk|yaml|py|ld))[:#](\d+)(?:[‐‑-](\d{1,4}))?`')
# ★ 无反引号的纯文本引用（很多文档写成 "出处: bl.c:317-318"）
BARE = re.compile(r'(?<![`/A-Za-z0-9_.\-])([A-Za-z0-9_\-]+\.(?:c|cpp|h|hpp))[:#](\d+)')
# ★ 两代标记都要认（否则重跑会重复追加）
APPHDRS = ("\n---\n\n## 源码附录", "\n---\n\n## 标注源码")

def strip_appendix(t):
    cuts = [t.find(m) for m in APPHDRS]
    cuts = [c for c in cuts if c >= 0]
    return (t[:min(cuts)].rstrip() + "\n") if cuts else t

def clean(md):
    """把一行 markdown 变成适合当注释的纯文本"""
    s = re.sub(r'\[`([^`]+)`\]\(file://[^)]*\)', r'`\1`', md)
    s = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', s)
    s = re.sub(r'^\s*[-*|>#]+\s*', '', s)
    s = re.sub(r'\*\*|__|`', '', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s[:200]

def collect(docpath):
    """返回 {relpath: {line: [解释...]}}"""
    txt = strip_appendix(open(docpath, encoding='utf-8').read())
    lines = txt.split('\n')
    cited = collections.defaultdict(lambda: collections.defaultdict(list))
    for i, ln in enumerate(lines):
        for m in LINK.finditer(ln):
            rel = None
            # 已解析的链接里含绝对路径 → 从中取相对 PX4 的路径
            p = m.group(3)
            for pat in ("PX4-Autopilot/",):
                j = p.find(pat)
                if j >= 0: rel = p[j+len(pat):]
            rel = rel or m.group(1)
            l1 = int(m.group(2))
            # 解释 = 该行 + 紧邻的上一行（若也是解释性文字）
            note = clean(lines[i])
            if i > 0 and lines[i-1].strip() and not lines[i-1].strip().startswith('```'):
                prev = clean(lines[i-1])
                if prev and prev not in note and len(prev) > 12:
                    note = prev + " ┃ " + note
            cited[rel][l1].append(note)
        # ★ 再扫不带反引号的纯文本引用（如 "出处: bl.c:317-318"）
        for m in BARE.finditer(ln):
            name, l1s = m.group(1), m.group(2)
            if "`" in ln and f"`{name}:{l1s}`" in ln:  # 已由上面处理
                continue
            l1 = int(l1s)
            rel2 = None
            for rp in (f"platforms/nuttx/src/bootloader/stm/stm32_common/{name}",
                       f"platforms/nuttx/src/bootloader/common/{name}"):
                if os.path.exists(os.path.join(PX4, rp)): rel2 = rp; break
            if rel2 is None: continue
            note = clean(ln)
            if note: cited[rel2].setdefault(l1, []).append(note)
    return cited

def emit(docpath, cited):
    if not cited: return 0
    out = ["", "---", "", "## 标注源码（代码 + 本文档对它的解释）", "",
           "> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。",
           "> 行号可点，直接跳到 PX4 源码那一行。", ""]
    n = 0
    for rel in sorted(cited):
        p = os.path.join(PX4, rel)
        if not os.path.exists(p): continue
        src = open(p, encoding='utf-8', errors='replace').read().split('\n')
        out.append(f"### `{rel}`")
        out.append("")
        for l1 in sorted(cited[rel]):
            if l1 < 1 or l1 > len(src): continue
            lo = max(1, l1 - 3); hi = min(len(src), l1 + 3)
            out.append(f"**↓ 文档在讲这里：**[`{rel}:{l1}`](file://{quote(p, safe='/')}#L{l1})")
            out.append("")
            out.append("```c")
            for k in range(lo, hi + 1):
                mark = "▶" if k == l1 else " "
                out.append(f"{mark}{k:5d} │ {src[k-1]}")
            out.append("```")
            for note in cited[rel][l1][:2]:
                if note: out.append(f"> **说明**：{note}")
            out.append("")
            n += 1
    # ★★ 必须先读、后打开写入（open('w') 会立即清空文件；写成一行的
    #    open(p,'w').write(doc) 会先截断再读 ⇒ 读到空串 ⇒ 正文被清空。这个坑真踩过。)
    body = strip_appendix(open(docpath, encoding='utf-8').read()).rstrip()
    with open(docpath, 'w', encoding='utf-8') as fh:
        fh.write(body + "\n" + "\n".join(out))
    return n

if __name__ == "__main__":
    tot = 0
    for f in sorted(glob.glob(sys.argv[1] + "/**/*.md", recursive=True)):
        # ★★ 跳过 03_moc：MOC 层只管流程，代码已归位到 02
        if os.path.normpath(f).replace(os.sep, "/").startswith("03_moc/"):
            continue
        k = emit(f, collect(f))
        if k: print(f"{f:62s} {k:4d} 处标注"); tot += k
    print(f"\n合计 {tot} 处标注源码")
