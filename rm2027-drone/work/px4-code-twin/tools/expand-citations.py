#!/usr/bin/env python3
"""v3：修复"错文件"问题。
关键改动：先用【全部文档的全路径引用】建 basename→路径 的【频率表】，
裸名优先命中频率最高者（文档自己引用最多的那个），只在完全无记录时才搜文件系统。
兜底搜索也改成【优先 rm2027 / px4 独有路径】，且排除 boards/ark 等无关板。"""
import re, os, sys, glob, collections
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _root import source_root   # ★ 源码根只在 tools/source-root.conf 维护
PX4 = source_root()

CITE = re.compile(r'`?([A-Za-z0-9_./\-]+\.(?:c|cpp|h|hpp|md|yaml|cmake|txt|py|ld|mk|px4board|defconfig|json|in|sh))[:#](\d+)(?:[‐‑-](\d{1,4}))?`?')

# ★ 人工钉死的消歧表：这些裸名在本套文档语境里有唯一正确解
OVERRIDE = {
    # bootloader/flash 语境里的 main.c = STM32 芯片族实现（APP_SIZE_MAX @:86、ispageerased @:484）
    "main.c": "platforms/nuttx/src/bootloader/stm/stm32_common/main.c",
}

def strip_old(txt):
    i = txt.find("\n---\n\n## 源码附录")
    return (txt[:i].rstrip() + "\n") if i >= 0 else txt

def build_freq(files):
    freq = collections.defaultdict(collections.Counter)
    for f in files:
        for m in CITE.finditer(open(f, encoding='utf-8').read()):
            p = m.group(1)
            if "/" in p and os.path.exists(os.path.join(PX4, p)):
                freq[os.path.basename(p)][p] += 1
    return freq

def main(root):
    files = sorted(glob.glob(root + "/**/*.md", recursive=True))
    FREQ = build_freq(files)
    # 每个 basename 选"文档里出现最多"的路径；并列时优先 rm2027 / 非 boards/ark
    def best(bn):
        c = FREQ.get(bn)
        if not c: return None
        def rank(kv):
            p, n = kv
            # ★ 本套文档全在讲 rm2027 → 含 rm2027 的路径【无条件优先】
            #   其次排除其它板（ark/matek/px4/holybro…）的同名文件，最后才比频率
            isrm = ("rm2027" in p)
            other_board = p.startswith("boards/") and not isrm
            return (isrm, not other_board, n, -p.count('/'))
        return max(c.items(), key=rank)[0]
    FS = None
    def fs_find(bn):
        nonlocal FS
        if FS is None:
            FS = collections.defaultdict(list)
            for r, dirs, fs in os.walk(PX4):
                dirs[:] = [d for d in dirs if d != '.git']
                for fn in fs: FS[fn].append(os.path.relpath(os.path.join(r, fn), PX4))
        hits = FS.get(bn, [])
        if not hits: return None
        hits = sorted(hits, key=lambda p: (p.startswith('build/'), 'rm2027' not in p, len(p)))
        return hits[0]
    tot = miss = 0; misslist = []
    for path in files:
        txt = strip_old(open(path, encoding='utf-8').read())
        own = {}
        # ★ 目录亲和度：本文档其它全路径引用都在哪些目录下（用于消歧裸名 main.c / init.c / CMakeLists.txt）
        affin = collections.Counter()
        for m in CITE.finditer(txt):
            p = m.group(1)
            if "/" in p and os.path.exists(os.path.join(PX4, p)):
                own.setdefault(os.path.basename(p), p)
                d = os.path.dirname(p)
                while d and d != '/':
                    affin[d] += 1; d = os.path.dirname(d)
        def best_affine(bn):
            """在全局频率表里挑'目录与本文档最亲和'的那个"""
            c = FREQ.get(bn)
            if not c: return None
            def score(kv):
                p, n = kv
                d = os.path.dirname(p); best = 0
                while d and d != '/':
                    best = max(best, affin.get(d, 0)); d = os.path.dirname(d)
                return (best, n)
            top = max(c.items(), key=score)
            return top[0] if score(top)[0] > 0 else None
        seen, rows = set(), []
        for m in CITE.finditer(txt):
            f, l1, l2 = m.group(1), int(m.group(2)), m.group(3)
            bn = os.path.basename(f)
            rel = None
            if "/" in f and os.path.exists(os.path.join(PX4, f)):
                rel = f                                    # ① 全路径，直接用
            if rel is None: rel = OVERRIDE.get(bn)         # ★ ①.5 人工钉死表
            if rel is None: rel = own.get(bn)              # ② 本文档自己的全路径引用
            if rel is None:                                # ③ ★ 文件系统里的本板路径优先
                RM = os.path.join(PX4, "boards/rm2027")
                for r, dirs, fs in os.walk(RM):
                    if bn in fs: rel = os.path.relpath(os.path.join(r, bn), PX4); break
            if rel is None: rel = best_affine(bn)          # ④ ★ 目录亲和度
            if rel is None: rel = best(bn)                 # ⑤ 全局频率
            if rel is None: rel = fs_find(bn)              # ⑤ 文件系统兜底
            if rel is None: miss += 1; misslist.append(f); continue
            key = (rel, l1, l2)
            if key in seen: continue
            seen.add(key)
            try: lines = open(os.path.join(PX4, rel), encoding='utf-8', errors='replace').read().split('\n')
            except Exception: miss += 1; continue
            hi = int(l2) if (l2 and int(l2) >= l1 and int(l2)-l1 < 8) else l1
            seg = [lines[n-1].rstrip()[:200] for n in range(l1, min(hi, len(lines))+1) if n-1 < len(lines)]
            if not seg: miss += 1; misslist.append(f); continue
            rows.append((rel, l1, seg))
        out = ["", "---", "", "## 源码附录（自动生成 · 不用翻文件）", "",
               f"> 由 `expand3.py` 从本文的 `file:line` 引用生成，共 **{len(rows)}** 条。",
               "> 格式：**`源码：<文件>:<行>`** 紧跟该行（或区间）原文。",
               "> 裸文件名（如 `bl.c`）由本套文档中出现过的全路径引用推定；**已排除其它板（ark 等）的同名文件**。", ""]
        for rel, l1, seg in sorted(rows, key=lambda r: (r[0], r[1])):
            out.append(f"**源码：`{rel}:{l1}`**"); out.append("```"); out.extend(seg); out.append("```"); out.append("")
        open(path, 'w', encoding='utf-8').write(txt.rstrip() + "\n" + "\n".join(out))
        tot += len(rows)
        print(f"{path:62s} {len(rows):4d} 条")
    print(f"\n合计 {tot} 条，未解析 {miss} 条")
    if misslist: print("未解析 top:", collections.Counter(misslist).most_common(8))

if __name__ == "__main__": main(sys.argv[1])
