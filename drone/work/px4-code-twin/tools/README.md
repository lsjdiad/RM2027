# tools/ · code-twin 维护脚本

## `expand-citations.py` —— 把 `file:line` 引用展开成源码附录

**用途**：每篇文档末尾的「## 源码附录」就是它生成的 —— 把文里所有 `file:line`
逐个查到 PX4 源码，贴出该行（或该区间）原文，格式 `源码：<文件>:<行>`。
**⇒ 这样读文档时不用翻源码。**

**重跑**（改完文档后）：
```bash
cd work/px4-code-twin
python3 tools/expand-citations.py .
```
**幂等**：会先删掉旧的附录再重新生成。

### 裸文件名怎么消歧（这套规则是踩出来的）
按优先级：
```
① 全路径引用          直接用
①.5 OVERRIDE 表       人工钉死（如 main.c → stm32_common/main.c）
② 本文档自己的全路径引用  同 basename 的
③ 文件系统里的本板路径   boards/rm2027/** 优先
④ 目录亲和度           候选目录与本文档其它引用重合度最高者
⑤ 全局频率            所有文档里出现最多的那个
⑥ 文件系统兜底
```sh
**⚠️ 三条踩过的坑**：
1. **别只按"频率"或"字母序"取** —— 会把 `hw_config.h` 解析到 `boards/ark/fpv/`、
   把 `main.c` 解析到 `canbootloader/uavcan/`（CAN bootloader），**指向完全不相关的代码**。
2. **行号过滤不够** —— `canbootloader/uavcan/main.c` 有 1409 行，比 `stm32_common/main.c`(829)
   还长，靠"行号在范围内"筛不掉。
3. **必须抽查输出** —— 生成后务必 grep 一遍附录里的路径前缀，看有没有其它板的文件混进来
   （`boards/ark` / `boards/matek` 若出现，确认是不是文档**故意**引用的参照板）。

### 已知残留
`fmc.c`（NuttX FMC 驱动，本树里路径不同）、`CMakeLists.txt`（全仓几百个，裸名本身无解）、
`stm32_start.c` 等约 39 条无法解析 —— 生成时会跳过，属正常。

---

## `link-sources.py` —— 把 `file:line` 变成**可点击跳转到源码那一行**的链接

**用途**：文档里每个 `` [`Makefile:237`](README.md#^src-Makefile-237) `` 都变成
``[`Makefile:237`](README.md#^src-Makefile-237)`` ——
**在 VS Code / Obsidian 里点一下就跳到那一行。**

**重跑**（改完文档后，**顺序：先 `link-sources.py` 再 `expand-citations.py`**）：
```bash
python3 tools/link-sources.py .          # 加跳转链接（幂等）
python3 tools/expand-citations.py .      # 再生成文末源码附录
```
**幂等**：先把已有 `file://` 链接还原成裸引用，再加链接。

### ⚠️ 两个必须知道的坑（都真踩过）
1. **`link-sources.py` 绝对不能"截掉附录再写回"** —— 第一版这么干，**一次删掉 8240 行附录**。
   现在改成"全量处理、不截断"，并从 git 回滚过一次。
   **⇒ 跑完务必 `grep -c "## 源码附录" */*.md` 确认篇数没变。**
2. **裸文件名要按"行号可行性"筛候选** —— 全仓有 **2433 个** `CMakeLists.txt`、
   多个 `main.c`/`init.c`。只按频率或目录亲和度挑会挑错（[`CMakeLists.txt:147`](README.md#^src-CMakeLists-txt-147)
   曾被解析到一个只有几十行的子文件）。
   **现在：先过滤掉"行数 < 被引用行号"的候选，再按 钉死表 > 本板 > 亲和度 > 频率 排。**

### 钉死表（`OVERRIDE`）
```python
"main.c"        → platforms/nuttx/src/bootloader/stm/stm32_common/main.c
"CMakeLists.txt"→ CMakeLists.txt                      # PX4 根目录那个（544 行）
```sh
**这份表是靠"内容对得上"逐条验证出来的**，不是猜的：
`根:147 define_property(GLOBAL PROPERTY PX4_MODULE_LIBRARIES)`、
`根:429 add_subdirectory(msg EXCLUDE_FROM_ALL)`、`stm32_common/main.c:484 up_progmem_ispageerased`。

### 抽查方法（改完请照做）
```bash
# 随机抽 8 条，打印目标行，人工核对是否对得上文档在讲的东西
python3 - <<'EOF'
import re,os,glob,urllib.parse,random
PX4="源码根（见 `tools/source-root.conf`）"
L=[(f,m.group(1),m.group(2),m.group(3),m.group(4)) for f in glob.glob("**/*.md",recursive=True)
   for m in re.finditer(r'\[`([^`]+?):(\d+)`\]\(file://([^)#]+)#L(\d+)\)', open(f,encoding="utf-8").read())]
for f,n,a,p,b in random.sample(L,8):
    print(f"{n}:{a} →", open(urllib.parse.unquote(p),encoding="utf-8",errors="replace").read().split("\n")[int(b)-1].strip()[:70])
EOF
```

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-147"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:147`](README.md#^src-CMakeLists-txt-147)

```c
   144 │ string(REGEX MATCH "g([a-f0-9]+)$" GIT_HASH "${PX4_GIT_TAG}")
   145 │ set(PX4_GIT_HASH ${CMAKE_MATCH_1})
   146 │ 
▶  147 │ define_property(GLOBAL PROPERTY PX4_MODULE_LIBRARIES
   148 │                  BRIEF_DOCS "PX4 module libs"
   149 │                  FULL_DOCS "List of all PX4 module libraries"
   150 │                  )
```
> **说明**：2. 裸文件名要按"行号可行性"筛候选 —— 全仓有 2433 个 CMakeLists.txt、 ┃ 多个 main.c/init.c。只按频率或目录亲和度挑会挑错（CMakeLists.txt:147
^src-CMakeLists-txt-147

### `Makefile`
<a id="src-Makefile-237"></a>
**↓ 文档在讲这里：**[`Makefile:237`](README.md#^src-Makefile-237)

```c
   234 │ endef
   235 │ 
   236 │ # Get a list of all config targets boards/*/*.px4board
▶  237 │ ALL_CONFIG_TARGETS := $(shell find boards -maxdepth 3 -mindepth 3 -name '*.px4board' -print | sed -e 's|boards\/||' | sed -e 's|\.px4board||' | sed -e 's|\/|_|g' | sort)
   238 │ 
   239 │ # ADD CONFIGS HERE
   240 │ # --------------------------------------------------------------------
```
> **说明**：用途：文档里每个 Makefile:237 都变成
> **说明**：用途：文档里每个 Makefile:237 都变成 ┃ Makefile:237 ——
^src-Makefile-237
