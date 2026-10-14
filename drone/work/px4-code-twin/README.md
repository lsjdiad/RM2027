# RM2027 无人机 · PX4 代码数字孪生

> 对应飞控源码 `源码根（见 `tools/source-root.conf`）`（板级 `boards/rm2027/fmu-h743`）
> 架构与引用规则照搬 `RM_note/rm-electric-knowledge-base`（四层 + wikilink）

---

## 四层架构

```
00_raw/          原始素材（只读）
                 上游源码、数据手册、官方文档 —— 不修改，作为知识链的最终出处

01_extracted/    提炼资料
                 从原始资料萃取的结构化知识（CMake 变量语义、NuttX 启动要素、H743 启动要点）
                 代码孪生层遇到新概念时链接回这里

02_code_twin/    代码数字孪生
                 ★ 每个源文件对应一篇 MD，镜像项目目录结构
                 摘关键代码片段 + 逐段解析；首次遇到某语法时链接回 01 层

03_moc/          多维度入口
                 ★ 按【构建顺序】与【执行顺序】组织，链接到 02 层各文件
```

```
04_notes/        开发经验（独立于四层）
```

**引用规则**：第 N 层只能向下引用第 N−1 层，不可反向。
所有跨文件引用使用**标准 Markdown 链接**（方括号标签 + 圆括号相对路径），
路径**相对本文件所在目录** —— 在编辑器里直接点就能跳，**不需要 Obsidian**。
引用 `work/` 下其它文档时用 `../../` 回到 `work/`。

---

## ★ 本套文档的视角：**程序运行时**

**不按"目录树"讲，按"执行顺序"讲。** 每一篇都回答同一个问题：

> **当系统跑到这一步时，控制权在哪、下一条指令跳到哪、我看到的现象由谁产生。**

**⇒ 每篇末尾都有「跳转」小节**，给出下一步该读哪篇（执行序意义上的下一步），而不是目录意义上的下一个文件。

---

## 阅读入口

| 入口 | 看什么 | 什么时候读 |
|---|---|---|
| [03_moc/00-build-walkthrough](03_moc/00-build-walkthrough.md) | **构建流程**：CMake 变量怎么按"板型"展开 → 编出什么 | 想懂"这块板子是怎么被编出来的" |
| [03_moc/01-poweron-walkthrough](03_moc/01-poweron-walkthrough.md) | **上电到飞行**：复位向量 → bootloader → NuttX → rcS → 各模块 | ★ **主线**：想懂"开机后发生了什么" |
| [03_moc/02-sensor-flow](03_moc/02-sensor-flow.md) | **六类传感器的信息流**：电机/陀螺/磁/气压/双陀螺/遥控 端到端 | 想懂"数据从硬件到控制律怎么走" |
| [03_moc/03-module-map](03_moc/03-module-map.md) | **module 层怎么理解**：uORB 总线、工作队列、启动依赖 | 想懂"那么多模块是怎么协同的" |
| [03_moc/04-params-map](03_moc/04-params-map.md) | **参数体系**：定义在哪、怎么落盘、怎么被读 | 想懂"改一个参数背后发生了什么" |

---

## ★ 我该按什么顺序学（含"你可能不会的语法"）

**[`04_notes/语法盲点审计.md`](04_notes/语法盲点审计.md)** —— 按"离裸机 C + CubeMX 经验有多远"
逐类打分，列出【要补的 Top 6】与【需要改写的 5 处】。
**⇒ 遇到看不懂的语法，先翻这一篇；里面标了"已讲 / 缺讲 / 不用讲"。**

---

## 01 层覆盖范围（提炼知识 —— 语法不懂时看这里）

| 目录 | 篇数 | 说明 |
|---|---|---|
| [`01_extracted/cmake/`](01_extracted/cmake/) | **4** | [`cmake-syntax`](01_extracted/cmake/cmake-syntax.md) ★ **CMake 语言**（`function` vs `macro` 作用域 / `GLOBAL` / `PARENT_SCOPE` / `if()` 的坑，含**实测**）· [`01-px4-cmake-organization`](01_extracted/cmake/01-px4-cmake-organization.md) · [`02-build-dir-map`](01_extracted/cmake/02-build-dir-map.md) · [`03-kconfig-bridge`](01_extracted/cmake/03-kconfig-bridge.md) |
| [`01_extracted/make/`](01_extracted/make/) | **1** | [`gnu-make-syntax`](01_extracted/make/gnu-make-syntax.md) ★ **GNU Make 语言**（`eval`/`call`/`patsubst`/`define`/`$(shell)`/`$(if)`/赋值四式/`override`/`$@`/`$$`，含**实测**） |
| [`01_extracted/cmake/`](01_extracted/cmake/) 另有 | **+1** | [`px4-global-variables`](01_extracted/cmake/px4-global-variables.md) ★ **又关键又全局的构建变量**（T1: `PX4_SOURCE_DIR`·`PX4_BINARY_DIR`·`PX4_BOARD_DIR`·`PX4_PLATFORM`；★T3 枢纽：`CONFIG`·`PX4_BOARD_NAME`·`config_module_list` —— **引用少但决定一切**，含实测引用次数） |
| [`01_extracted/c/`](01_extracted/c/) | **1** | [`px4-c-macros`](01_extracted/c/px4-c-macros.md) ★ **C 宏与属性**（`__EXPORT` / `__attribute__` 最常撞的 6 种 / ★`#` 字符串化与 `##` 拼接的真实实例 / `##__VA_ARGS__` 逗号吞噬，含**实测**） |
| [`01_extracted/uorb/`](01_extracted/uorb/) | **1** | [`uorb-mechanism`](01_extracted/uorb/uorb-mechanism.md) ★ **uORB 与模块框架**（`.msg`→生成两半 / ★三份 uORB.h 的坑 / `ORB_ID`·`ORB_DECLARE`·`ORB_DEFINE` / 发布订阅语义 last-value / `ModuleBase`+`WorkItem` 骨架 / `wq_configurations` 全集） |
| [`01_extracted/nuttx/`](01_extracted/nuttx/) | **4** | `00-poweron-chain` · `bootloader-vs-app` · `romfs` · `nsh-and-rcS` |
| [`01_extracted/stm32/`](01_extracted/stm32/) | **4** | [`startup-and-crt`](01_extracted/stm32/startup-and-crt.md) ★ **复位→`__start()`→C 运行时就绪**（.bss 清零 / ★为什么必须搬 .data：链接脚本 `AT > FLASH` 的 LMA≠VMA / 栈堆从哪来）· `00-reset-clock-peripherals` · `vtor-vector-tables` · `flash-layout` |

**⇒ 规则**（照 RM_note）：**语法/概念属于 01 层；02 层摘代码 + 逐段解析，遇到新语法【链接回 01 层】。**

---

## 02 层覆盖范围

| 目录 | 对应源码 | 说明 |
|---|---|---|
| `02_code_twin/bootloader/` | `platforms/nuttx/src/bootloader/` | 上电最先跑的那段 |
| `02_code_twin/build/` | **8 篇**：`Makefile` · `CMakeLists` · `cmake-kconfig`(21 条) · `nuttx-build`(12) · `drivers-build`(14) · `artifacts`(8) · `romfs-and-tools`(7) · `board-build`(4) | ★ **构建全链的行号详解** |
| `02_code_twin/uorb/` | `uorb-internals` · `msg-build` | uORB 实现与 `.msg` 生成 |
| `02_code_twin/framework/` | `work-queue` · `platform-common` | 工作队列 / 平台公共框架 |
| `02_code_twin/board/` | `boards/rm2027/fmu-h743/`（25 个文件） | ★ 本板专属 |
| `02_code_twin/modules/` | `src/modules/`（sensors/ekf2/commander/control_allocator/mavlink…） | module 层 |
| `02_code_twin/drivers/` | `src/drivers/`（hxy42688p / h104_imu / bmi270 / ist8310 / spa06 / dshot…） | 硬件驱动 |
| `02_code_twin/params/` | `src/lib/parameters/` + 生成参数表 | 参数机制 |

> ★ **分层约定**：`01_extracted/` 讲语法/机制通则 · `02_code_twin/` 讲**某个文件的行号在干什么** · `03_moc/` **只讲流程**（代码与逐行解释一律归位到 02，MOC 篇末尾有「源码在哪」指针表）。

---

## 与其他文档的关系

| 文档 | 关系 |
|---|---|
| `work/PX4改造-索引与纪律.md` | **纪律登记处**（踩坑结论）；本套是**执行视角的展开** |
| `work/驱动正确实现与手册对照.md` | 驱动 × 手册逐条对照（01 层的来源之一） |
| `work/PX4-rcS执行时序表.md` | rcS 阶段表；本套 `03_moc/01` 引用它 |
| `work/PX4-bootloader主流程时序图.md` | bootloader 决策序；本套 `03_moc/01` 引用它 |

---

## 源码附录（自动生成 · 不用翻文件）

> 由 `expand3.py` 从本文的 `file:line` 引用生成，共 **0** 条。
> 格式：**`源码：<文件>:<行>`** 紧跟该行（或区间）原文。
> 裸文件名（如 `bl.c`）由本套文档中出现过的全路径引用推定；**已排除其它板（ark 等）的同名文件**。
