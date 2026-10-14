#!/usr/bin/env python3
"""让锚点在 **Obsidian** 里能用（用户环境），并把链接统一成 Obsidian 的块引用形式。

【为什么需要】
  用户的 Obsidian 只认两种锚点：`#标题` 与 `#^块ID`；它【不解析】HTML 的 <a id="...">。
  所以每条标注块要【同时】给两种标记（HTML 给 VS Code/GitHub，块 ID 给 Obsidian）。

【每条标注块的目标形态】
    ### `文件路径`
    <a id="src-X"></a>                            ← HTML 锚点（标准解析器）
    **↓ 文档在讲这里：**[`文件:行`](本文件.md#^src-X)   ← Obsidian 块引用
    ```c
    ...代码...
    ```
    > **说明**：...
    ^src-X                                         ← 块 ID（紧贴内容，中间不能有空行）

【必须遵守的规则（都是实测踩出来的）】
  ① `^id` 与它附着的块之间【不能有空行】，否则 Obsidian 认不出来
  ② `### ` 标题出现时必须先收尾【上一块】并清空 cur_id，否则 ID 会重复
  ③ 段内链接→自指；【段外链接保留原目标】（03_moc 的代码已归位到 02，指向自己就错了）
  ④ 幂等：先清掉旧的 <a id> 与 ^id 再重建
  ⑤ 没有「标注源码」段的篇（如 03_moc）也要处理链接

用法: python3 tools/obsidianize-anchors.py . [--dry-run]
"""
import re, os, sys, glob

DRY = "--dry-run" in sys.argv
_dirs = [a for a in sys.argv[1:] if not a.startswith("--")]
os.chdir(_dirs[0] if _dirs else ".")

RE_HTML = re.compile(r'(?m)^[ \t]*<a id="(src-[A-Za-z0-9_\-]+)"></a>[ \t]*\n?')
RE_BLK = re.compile(r'(?m)^[ \t]*\^(src-[A-Za-z0-9_\-]+)[ \t]*\n?')
RE_TAG = re.compile(r'^\*\*↓ 文档在讲这里：\*\*\[`([^`]+?):(\d+)`\]')
RE_LINK = re.compile(r'\]\(([^)#\s]*\.md)#(\^?)src-([A-Za-z0-9_\-]+)\)')


def sid(rel, line):
    return "src-" + re.sub(r"[^A-Za-z0-9]+", "-", rel).strip("-") + f"-{line}"


def upgrade(m):
    """段外链接：只把 #src- 升级成 #^src-，【保留原目标】"""
    return f"]({m.group(1)}#^src-{m.group(3)})"


n_doc = n_blk = n_link = 0

for f in sorted(glob.glob("**/*.md", recursive=True)):
    s0 = open(f, encoding="utf-8").read()

    # ⑤ 没有标注段的篇：只升级链接形式
    if "## 标注源码" not in s0:
        n_link += len(RE_LINK.findall(s0))
        s1 = RE_LINK.sub(upgrade, s0)
        if not DRY and s1 != s0:
            open(f, "w", encoding="utf-8").write(s1)
        continue

    head, sec = s0.split("## 标注源码", 1)

    # ④ 幂等：清掉旧的两种标记
    sec = RE_HTML.sub("", sec)
    sec = RE_BLK.sub("", sec)

    lines = sec.split("\n")
    out, pending = [], []
    state = {"cur": None}

    def flush():
        global n_blk
        while pending and pending[-1].strip() == "":     # ① 紧贴
            pending.pop()
        out.extend(pending)
        if state["cur"]:
            out.append(f"^{state['cur']}")
            out.append("")
            n_blk += 1
        pending.clear()
        state["cur"] = None                              # ② 收尾后清空

    for ln in lines:
        if re.match(r"^### `", ln):                      # ②
            flush()
            pending.append(ln)
            continue
        m = RE_TAG.match(ln)
        if m:
            flush()
            state["cur"] = sid(m.group(1), int(m.group(2)))
            out.append(f'<a id="{state["cur"]}"></a>')
            n_doc += 1
            pending.append(ln)
            continue
        pending.append(ln)
    flush()

    # ③ 段外只升级形式；段内改自指
    head_up = RE_LINK.sub(upgrade, head)
    n_link += len(RE_LINK.findall(head))
    me = os.path.basename(f)

    def self_ref(m):
        global n_link
        n_link += 1
        return f"]({me}#^src-{m.group(3)})"

    new_sec = "## 标注源码" + RE_LINK.sub(self_ref, "\n".join(out))
    s1 = head_up + new_sec
    if not DRY and s1 != s0:
        open(f, "w", encoding="utf-8").write(s1)

print(f"{'【干跑】' if DRY else '✅ '}HTML 锚点 {n_doc} · 块 ID {n_blk} · 链接 {n_link}")
