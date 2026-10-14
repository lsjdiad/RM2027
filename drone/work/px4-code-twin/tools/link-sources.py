#!/usr/bin/env python3
"""v2（修复 v1 把附录删掉的 bug）：不截断文档，全量处理。
幂等：先把已有 file:// 链接还原成裸引用，再加链接。附录标题也会变成链接。"""
import re, os, sys, glob, collections
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _root import source_root   # ★ 源码根只在 tools/source-root.conf 维护
PX4 = source_root()
from urllib.parse import quote

CITE = re.compile(r'`((?:[A-Za-z0-9_./\-]+/)?(?:[A-Za-z0-9_\-]+\.(?:c|cpp|h|hpp|md|yaml|cmake|txt|py|ld|mk|px4board|defconfig|json|in|sh)|Makefile|Kconfig|Dockerfile))[:#](\d+)(?:[‐‑-](\d{1,4}))?`')
# ★ 幂等关键：把【所有已有的链接形式】都还原成裸引用，否则会越包越多层
#   · file:// 外链   · 站内锚跳转（.md#src-…）—— 后者曾漏掉，导致 link-sources 再包一层 ⇒ 双嵌套
UNLINK = re.compile(r'\[`([^`]+?):(\d+)`\]\([^)]*(?:file://|\.md#\^?src-)[^)]*\)')
OVERRIDE = {
    # bootloader/flash 语境的 main.c = STM32 芯片族实现（APP_SIZE_MAX @:86、ispageerased @:484）
    "main.c": "platforms/nuttx/src/bootloader/stm/stm32_common/main.c",
    # ★ 裸 CMakeLists.txt = PX4 根目录那个（实测：147 define_property / 315 EXPORT_COMPILE_COMMANDS /
    #   429 add_subdirectory(msg) / 480 foreach(config_module_list) —— 全仓 2433 个同名文件，只有根对得上）
    "CMakeLists.txt": "CMakeLists.txt",
}

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
    FS = None
    CNT = {}
    def fs_find(bn):
        nonlocal FS
        if FS is None:
            FS = collections.defaultdict(list)
            for r, dirs, fs_ in os.walk(PX4):
                dirs[:] = [d for d in dirs if d != '.git']
                for fn in fs_: FS[fn].append(os.path.relpath(os.path.join(r, fn), PX4))
        h = sorted(FS.get(bn, []), key=lambda p: (p.startswith('build/'), 'rm2027' not in p, len(p)))
        return h[0] if h else None
    tot = miss = 0
    for path in files:
        txt = open(path, encoding='utf-8').read()
        txt = UNLINK.sub(lambda m: f"`{m.group(1)}:{m.group(2)}`", txt)      # ① 幂等：先还原
        affin = collections.Counter(); own = {}
        for m in CITE.finditer(txt):
            p = m.group(1)
            if "/" in p and os.path.exists(os.path.join(PX4, p)):
                own.setdefault(os.path.basename(p), p)
                d = os.path.dirname(p)
                while d and d != '/': affin[d] += 1; d = os.path.dirname(d)
        def nlines(rel):
            k = ("N", rel)
            if k not in CNT:
                try: CNT[k] = sum(1 for _ in open(os.path.join(PX4, rel), encoding='utf-8', errors='replace'))
                except Exception: CNT[k] = 0
            return CNT[k]
        def resolve(f, line):
            bn = os.path.basename(f)
            if "/" in f and os.path.exists(os.path.join(PX4, f)): return f
            # ① 收集所有候选
            cands = []
            if bn in own: cands.append(own[bn])
            if bn in OVERRIDE: cands.append(OVERRIDE[bn])
            for r, dirs, fs_ in os.walk(os.path.join(PX4, "boards/rm2027")):
                if bn in fs_: cands.append(os.path.relpath(os.path.join(r, bn), PX4))
            c = FREQ.get(bn)
            if c: cands += [p for p, _ in c.most_common(12)]
            cands = list(dict.fromkeys(cands))
            # ② ★ 行号可行性过滤：文件必须有这么多行
            feas = [p for p in cands if nlines(p) >= line]
            if len(feas) == 1: return feas[0]
            pool = feas if feas else cands
            if not pool: return fs_find(bn)
            # ③ 排序：本板 > 钉死表 > 目录亲和度 > 频率
            def sc(p):
                d = os.path.dirname(p); aff = 0
                while d and d != '/': aff = max(aff, affin.get(d, 0)); d = os.path.dirname(d)
                nmatch = int(p in own.values()) + int(p == OVERRIDE.get(bn))
                return (int(p == OVERRIDE.get(bn)), nmatch, ("rm2027" in p), aff, FREQ.get(bn, {}).get(p, 0))
            return max(pool, key=sc)
        def repl(m):
            nonlocal tot, miss
            f, l1 = m.group(1), int(m.group(2))
            rel = resolve(f, l1)
            if rel is None: miss += 1; return m.group(0)
            tot += 1
            return f"[`{f}:{l1}`](file://{quote(os.path.join(PX4, rel), safe='/')}#L{l1})"
        new = CITE.sub(repl, txt)
        open(path, 'w', encoding='utf-8').write(new)
    print(f"✅ 链接 {tot} 条，未解析 {miss} 条")

if __name__ == "__main__": main(sys.argv[1])
