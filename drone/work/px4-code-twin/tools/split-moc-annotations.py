#!/usr/bin/env python3
"""把某一篇 03_moc 的「标注源码」段按源文件【归位到 02 层】（通用版）。

设计：
  ① 每个源文件算一个「归属组」（按它的模块/目录）
  ② 若某篇现有 02 篇已覆盖【同一组】的文件 ⇒ 并入那篇
  ③ 否则按组在 02 层建新篇
  ④ 从 MOC 篇删掉标注段，换成「源码在哪」指针表
  ⑤ 每个块强制自带 `### 文件` 标题（原格式常有"一个标题挂多条"，照搬会段/标注错配）

用法:
  python3 tools/split-moc-annotations.py 03_moc/04-params-map.md [--dry-run]
"""
import re, os, sys, glob, collections

args = [a for a in sys.argv[1:] if not a.startswith("--")]
DRY = "--dry-run" in sys.argv
SRC = args[0] if args else None
if not SRC or not os.path.exists(SRC):
    print("用法: python3 tools/split-moc-annotations.py <03_moc/某篇.md> [--dry-run]")
    sys.exit(1)


def group_of(f):
    for pref, name in (
        ("src/drivers/", "drivers"), ("src/modules/", "modules"),
        ("src/lib/", "lib"), ("src/systemcmds/", "systemcmds"),
        ("platforms/common/uORB/", "uorb"), ("platforms/common/px4_work_queue/", "workqueue"),
        ("platforms/common/include/px4_platform_common/", "framework"),
        ("platforms/common/", "framework"), ("platforms/nuttx/src/px4/", "platform-nuttx"),
        ("platforms/nuttx/", "build-nuttx"), ("platforms/posix/", "platform-posix"),
        ("boards/", "board"), ("msg/", "uorb-msg"),
        ("ROMFS/", "romfs-tools"), ("Tools/", "romfs-tools"),
        ("build/", "artifacts-build"), ("cmake/", "cmake-build"),
    ):
        if f.startswith(pref):
            rest = f[len(pref):]
            if name in ("drivers", "modules", "lib", "systemcmds"):
                # ★ 若该目录下是【散落文件】(rest 里没有 /)，归到该层的 README，别当成模块（否则会生成 drv_dshot.h.md 这种怪名）
                return f"{name}/{rest.split('/')[0]}" if "/" in rest else name
            return name
    if f in ("CMakeLists.txt", "Makefile"):
        return "cmake-build"
    return "misc"


def page_of(group):
    known = {
        "cmake-build": "02_code_twin/build/cmake-kconfig.md",
        "build-nuttx": "02_code_twin/build/nuttx-build.md",
        "romfs-tools": "02_code_twin/build/romfs-and-tools.md",
        "artifacts-build": "02_code_twin/build/artifacts.md",
        "board": "02_code_twin/build/board-build.md",
        "uorb": "02_code_twin/uorb/uorb-internals.md",
        "uorb-msg": "02_code_twin/uorb/msg-build.md",
        "workqueue": "02_code_twin/framework/work-queue.md",
        "framework": "02_code_twin/framework/platform-common.md",
        "platform-nuttx": "02_code_twin/framework/nuttx-px4.md",
        "platform-posix": "02_code_twin/framework/posix.md",
        "misc": "02_code_twin/misc.md",
    }
    if group in known:
        return known[group]
    if "/" not in group:                      # 散落文件（如 drivers 根的 drv_dshot.h）
        return f"02_code_twin/{group}/loose.md"
    kind, name = group.split("/", 1)
    return f"02_code_twin/{kind}/{name}.md"


HEADER = {
"02_code_twin/uorb/uorb-internals.md":
"""# uORB 内部实现（`platforms/common/uORB/`）

> **层**：`02_code_twin/`（代码孪生）
> **范围**：`uORB.h` · `Publication.cpp` · `Subscription.hpp` · `uORBDeviceNode.hpp` · `uORBDeviceMaster.cpp`
>
> | 想看什么 | 去哪 |
> |---|---|
> | uORB 机制与三个宏（通则） | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) |
> | 传感器数据怎么流 | [`03_moc/02-sensor-flow`](../../03_moc/02-sensor-flow.md) |

---

""",
"02_code_twin/uorb/msg-build.md":
"""# `.msg` → 生成代码 的构建过程（`msg/`）

> **层**：`02_code_twin/`（代码孪生）
>
> | 想看什么 | 去哪 |
> |---|---|
> | `.msg` → 生成两半 的机制 | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) |

---

""",
"02_code_twin/framework/work-queue.md":
"""# 工作队列（`platforms/common/px4_work_queue/`）

> **层**：`02_code_twin/`（代码孪生）
>
> | 想看什么 | 去哪 |
> |---|---|
> | 工作队列机制与 `wq_configurations` 全集 | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) §7 |
> | 模块地图 | [`03_moc/03-module-map`](../../03_moc/03-module-map.md) |

---

""",
"02_code_twin/framework/platform-common.md":
"""# 平台公共框架（`platforms/common/`）

> **层**：`02_code_twin/`（代码孪生）
> **范围**：`module.h` · `i2c_spi_buses.h` · `param_macros.h` 等框架头
>
> | 想看什么 | 去哪 |
> |---|---|
> | 模块骨架（`ModuleBase` + `WorkItem`） | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) §6 |
> | C 宏与属性（`__EXPORT` / `##`） | [`01_extracted/c/px4-c-macros`](../../01_extracted/c/px4-c-macros.md) |

---

""",
"02_code_twin/misc.md": """# 其它（未归类的源文件）

> **层**：`02_code_twin/`（代码孪生）

---

""",
}


def header_for(target):
    if target in HEADER:
        return HEADER[target]
    kind = target.split("/")[1] if "/" in target else ""
    tips = {
        "drivers": "> | 想看什么 | 去哪 |\n> |---|---|\n> | 驱动层机制 | [`01_extracted/`](../../01_extracted/) |\n",
        "modules": "> | 想看什么 | 去哪 |\n> |---|---|\n> | 模块骨架与 uORB | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) |\n",
    }.get(kind, "")
    return (f"# `{os.path.basename(target)[:-3]}` —— 代码孪生\n\n"
            f"> **层**：`02_code_twin/`（代码孪生）\n{tips}\n---\n\n")


# ── 解析 MOC 篇的标注段 ──
s = open(SRC, encoding="utf-8").read()
if "## 标注源码" not in s:
    print(f"{SRC} 没有「标注源码」段（可能已治理）")
    sys.exit(0)
head, sec = s.split("## 标注源码", 1)

blocks = []
cur_file, buf = None, []


def flush():
    if buf and cur_file:
        joined = "\n".join(buf)
        m = re.search(r"\[`([^`]+?):(\d+)`\]", joined)
        if m:
            blocks.append((cur_file, int(m.group(2)), joined.strip()))
    buf.clear()


for ln in sec.split("\n"):
    m = re.match(r"^### `(.+?)`\s*$", ln)
    if m:
        flush()
        cur_file = m.group(1)
        buf.append(ln)
        continue
    buf.append(ln)
    if re.match(r"^\^src-[A-Za-z0-9_\-]+$", ln):
        flush()
flush()

# ── 现有 02 篇覆盖了哪些「组」 ──
group_pages = {}
for g in glob.glob("02_code_twin/**/*.md", recursive=True):
    t = open(g, encoding="utf-8").read()
    if "## 标注源码" not in t:
        continue
    for m in re.finditer(r"(?m)^### `(.+?)`", t.split("## 标注源码", 1)[1]):
        group_pages.setdefault(group_of(m.group(1)), g)

have = collections.defaultdict(set)
for g in glob.glob("02_code_twin/**/*.md", recursive=True):
    t = open(g, encoding="utf-8").read()
    if "## 标注源码" not in t:
        continue
    c = None
    for l in t.split("## 标注源码", 1)[1].split("\n"):
        mm = re.match(r"^### `(.+?)`", l)
        if mm:
            c = mm.group(1)
        m2 = re.match(r"^\*\*↓ 文档在讲这里：\*\*\[`([^`]+?):(\d+)`\]", l)
        if m2 and c:
            have[c].add(int(m2.group(2)))

targets = collections.defaultdict(list)
for f, line, text in blocks:
    grp = group_of(f)
    page = group_pages.get(grp) or page_of(grp)
    targets[page].append((f, line, text))

print(f"{SRC}: {len(blocks)} 条标注 → {len(targets)} 个落点")
for t in sorted(targets):
    n = len(targets[t])
    keep = [x for x in targets[t] if x[1] not in have.get(x[0], ())]
    print(f"   {n:3d} 条 → {t}   （去重 {n - len(keep)}，写入 {len(keep)}）")


def with_head(txt, f):
    return txt if re.match(r"^### `", txt) else f"### `{f}`\n{txt}"


for target, items in targets.items():
    keep = [x for x in items if x[1] not in have.get(x[0], ())]
    if not keep or DRY:
        continue
    new_sec = "\n\n".join(with_head(x[2], x[0]) for x in keep)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target):
        t = open(target, encoding="utf-8").read()
        if "## 标注源码" in t:
            pre, old = t.split("## 标注源码", 1)
            body = pre + "## 标注源码" + old.rstrip() + "\n\n" + new_sec + "\n"
        else:
            body = t.rstrip() + "\n\n## 标注源码\n\n" + new_sec + "\n"
    else:
        body = header_for(target) + "## 标注源码\n\n" + new_sec + "\n"
    open(target, "w", encoding="utf-8").write(body)

if not DRY:
    rows = []
    for target in sorted(targets):
        rel = os.path.relpath(target, os.path.dirname(SRC) or ".")
        rows.append(f"| `{target}` | [`{target}`]({rel}) |")
    pointer = (
        "## 源码在哪（本篇只讲流程；代码与逐行解释已归位到 02 层）\n\n"
        "> ★ **本篇每一条 `文件:行` 都能点** —— 它跳到 `02_code_twin/` 里对应的篇，代码旁边就是解释。\n"
        "> 三层各司其职：**01 讲语法/机制通则 · 02 讲某个文件的行号在干什么 · 03 只讲流程**。\n\n"
        "| 代码在 | 02 层的篇 |\n|---|---|\n" + "\n".join(rows) + "\n"
    )
    open(SRC, "w", encoding="utf-8").write(head.rstrip() + "\n\n" + pointer)
    print(f"\n✅ {SRC} 已去掉标注段并加指针（{len(blocks)} 条归位）")
