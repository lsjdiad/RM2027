# nsh / `rc.sysinit` / `rcS`：脚本是怎么被"执行"的

> **层**：01 提炼知识
> **素材**：`platforms/nuttx/NuttX/apps/system/nsh/nsh_main.c`、`apps/nshlib/nsh_init.c`、`apps/nshlib/nsh_script.c`、
> `apps/nshlib/nsh.h`、`ROMFS/px4fmu_common/init.d/rcS`（797 行）
> **配套**：`work/PX4-rcS执行时序表.md`（阶段表；本篇只讲**"脚本是怎么被跑起来的"**，不重复阶段表）

---

## 1. 从 `task_spawn("nsh_main")` 到 `rcS` 第一行：完整 6 跳

| # | 控制权在哪 | 代码位置 | 干了什么 |
|---|---|---|---|
| 1 | 新任务 `nsh_main` | [`apps/system/nsh/nsh_main.c:53`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-53)（源文件里是 `int main(...)`，编译期被 `-Dmain=nsh_main` 改名） | `:60-67` 调优先级到 `CONFIG_SYSTEM_NSH_PRIORITY`（`.config:2145` = 100） |
| 2 | `nsh_main` | `:71` → [`apps/nshlib/nsh_init.c:106`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-106) | `nsh_initialize()`：设提示符（`:117`）、readline（`:122`）… |
| 3 | `nsh_initialize` | [`nsh_init.c:146`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-146) | `CONFIG_NSH_ARCHINIT=y`（`.config:2106`）⇒ **`boardctl(BOARDIOC_INIT, 0)`** |
| 3a | → `boardctl` | `nuttx/boards/boardctl.c:366` | `case BOARDIOC_INIT:` ⇒ 调 **`board_app_initialize()`** |
| 3b | → ③ 板级 | [`boards/rm2027/fmu-h743/src/init.c:157`](../stm32/00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-157) | `px4_platform_init()`（`:160`）、DMA 分配器（`:163`）、LED（`:168-170`）、hardfault（`:172-174`）… |
| 4 | `nsh_initialize` | [`nsh_init.c:152`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-152) | `CONFIG_ETC_ROMFS` 且未禁用脚本 ⇒ `nsh_newconsole(false)` + **`nsh_sysinitscript()`** |
| 4a | → [`nsh_script.c:215`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-215) | `:221` | `nsh_script_redirect(vtbl, "sysinit", NSH_SYSINITPATH, false)` ⇒ **跑 `/etc/init.d/rc.sysinit`** |
| 5 | `nsh_initialize` | [`nsh_init.c:172`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-172) | **`nsh_initscript()`** ⇒ [`nsh_script.c:237`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-237) ⇒ `:253` `nsh_script_redirect(vtbl, "init", **NSH_INITPATH**, true)` |
| 6 | `nsh_main` | [`nsh_main.c:76`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-76) | `nsh_consolemain(argc, argv)` ⇒ **NSH 交互控制台**（`:78-83` 注释原话：*"should not return"*） |

**⇒ 所以真正的顺序是**：`board_app_initialize()`（C 代码先跑完）→ `rc.sysinit` → `rcS` → 交互 shell。
**在 `rcS` 的第一行被执行时，PX4 的平台初始化（`px4_platform_init()` / hrt / DMA）早就做完了。**

---

## 2. `NSH_INITPATH` 是怎么拼出来的（★ 三条宏的合成）

```
apps/nshlib/nsh.h:293   #ifdef CONFIG_ETC_ROMFS
apps/nshlib/nsh.h:295-297   #ifndef CONFIG_NSH_SYSINITSCRIPT → "init.d/rc.sysinit"
apps/nshlib/nsh.h:299-301   #ifndef CONFIG_NSH_INITSCRIPT     → "init.d/rcS"
apps/nshlib/nsh.h:304       #define NSH_SYSINITPATH  CONFIG_ETC_ROMFSMOUNTPT "/" CONFIG_NSH_SYSINITSCRIPT
apps/nshlib/nsh.h:307       #define NSH_INITPATH     CONFIG_ETC_ROMFSMOUNTPT "/" CONFIG_NSH_INITSCRIPT
```

**本板（app 构建）实际拼出来**：

| 片段 | 值 | 来源 |
|---|---|---|
| `CONFIG_ETC_ROMFSMOUNTPT` | `"/etc"` | `.config:711` |
| `CONFIG_NSH_INITSCRIPT` | `"init.d/rcS"` | `.config:2095`（Kconfig 默认值 `apps/nshlib/Kconfig:880`） |
| ⇒ **`NSH_INITPATH`** | **`/etc/init.d/rcS`** | — |
| `CONFIG_NSH_SYSINITSCRIPT` | `"init.d/rc.sysinit"` | `.config:2094`（Kconfig 默认 `:872`） |
| ⇒ **`NSH_SYSINITPATH`** | **`/etc/init.d/rc.sysinit`** | — |

### ★ 三个"容易搞错"的点

1. **`CONFIG_NSH_INITSCRIPT` 不在板级 defconfig 里**（grep `nuttx-config/nsh/defconfig` 无命中）。
   它是**Kconfig 的默认值**（`apps/nshlib/Kconfig:878`，default `"init.d/rcS"`），
   所以"我没配它"≠"它没有值"。**这也是改了它却看不到变化的原因**（改板级 defconfig 是改不动的）。
2. **[`nsh.h:299`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-299) 还有一层编译期兜底**：即使 `.config` 里没有这个键，也会被 `#ifndef` 补成 `"init.d/rcS"`。
3. **[`nsh.h:318`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-318) 的 `#else`**：如果没有 `CONFIG_ETC_ROMFS`，`NSH_INITPATH` 根本不存在、
   `nsh_initscript()` 也不会被编（[`nsh_script.c:236`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-236) 的 `#ifdef CONFIG_ETC_ROMFS`）
   ⇒ **bootloader 构建没有 ROMFS ⇒ 这一整块都不存在**（见 [01_extracted/nuttx/romfs](romfs.md)）。

---

## 3. `rc.sysinit` 与 `rcS` 的分工

| 脚本 | 路径 | 判据 | 执行/返回语义 |
|---|---|---|---|
| `rc.sysinit` | `/etc/init.d/rc.sysinit` | [`nsh_script.c:221`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-221) 传 `false` | **找不到不报错**（`:217-219` 注释原话："Do not log error output for a missing … script file"） |
| `rcS` | `/etc/init.d/rcS` | [`nsh_script.c:253`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-253) 传 `true` | 找不到**报错** |
| `rcS` 的幂等性 | — | [`nsh_script.c:242`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-242) | 用一个 `g_nsh_script_initialized` 标志 + `sched_lock()` 做"原子测试并置位" ⇒ **只会执行一次**，重复调用无害 |

**本板实测（已回验）**：`wc -c ROMFS/px4fmu_common/init.d/rc.sysinit` = **44 字节**，内容只有
`#!/bin/sh` + 两行注释。
⇒ **真机开机链的"脚本段"实际就是 `rcS` 一个文件**（`rcS` 共 797 行）。

> ⚠️ 注意 `rcS` 的注释（`rcS:14`）：**"COMMENT LINES ARE REMOVED BEFORE STORED IN ROMFS."**
> ⇒ 你在 ROMFS 里读到的 `rcS` 与源码树里的行数**不一定一致**。做行号核对时要以**源码树**为准。

---

## 4. `rcS` 里"接回 C 代码"的两个入口

`rcS` 不是纯 shell —— 它通过 **builtin 命令**调回 NuttX/PX4 的 C 函数：

| 行号 | 命令 | 接回哪里 |
|---|---|---|
| `rcS:58` | `ver all` | PX4 的 `ver` builtin（固件/硬件版本） |
| `rcS:204` | `param load-or-init $PARAM_BACKUP_FILE` | PX4 参数系统（落盘在 flash 扇区 15，见 [01_extracted/stm32/flash-layout](../stm32/flash-layout.md)） |
| `rcS:420-424` | source `rc.board_sensors`（③层） | ★ 本板自己的驱动拉起脚本；`:423` 的 `echo "Board sensors: …"` 是"文件进 ROMFS 了"的唯一判据 |
| `rcS:440` | `sensors start` | **真正的 `sensors` 模块**（module 层，见 [03_moc/03-module-map](../../03_moc/03-module-map.md)） |
| `rcS:446-449` | `if param compare -s EKF2_EN 1` → `:448 ekf2 start &` | EKF2 **后台**启动 |
| `rcS:797` | `mavlink boot_complete` | 通知地面站"启动完成"（`:795-796` 是注释） |

**⇒ "启动脚本"与"module 层"的接口就是 builtin 命令。**
脚本只负责**顺序**，实际功能全在 C/C++ 的 module 里。这也是 [03_moc/03-module-map](../../03_moc/03-module-map.md) 里
"rcS 的顺序 = 依赖顺序"那句话的机制来源。

---

## 5. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| 串口出现 `NuttX …` 版本行、然后一堆 `INFO [init] …` | `rcS` 里的 `ver all` 与各段 `echo` | `rcS:58`、`rcS:281`… |
| **看不到** `Board sensors:` 那一行 ⇒ 脚本没进 ROMFS | 构建期白名单，不是运行期 | → [01_extracted/nuttx/romfs](romfs.md) §4 |
| 刷了固件、脚本改了，板上却没变 | 脚本被**编进镜像**（ROMFS），不是从盘上读 | 同上 |
| `rc.sysinit` 里写什么都没效果 | 它是 44 字节空壳 | `work/PX4-rcS执行时序表.md:18` |
| 开机卡在某个 `param` 报错后还能起来 | `rcS:3 set +e`（脚本不因单条失败退出） | `rcS:3` |
| QGC 从"等待"变正常 | `rcS:795-797` 的 `mavlink boot_complete` | — |

---

## 跳转

- **执行序上一步**（谁把 `nsh_main` 拉起来、之前的内核链）→ [01_extracted/nuttx/00-poweron-chain](00-poweron-chain.md)。
- **`rcS` 的结构与每个阶段干了什么** → 既有素材 `work/PX4-rcS执行时序表.md`（**不要重复读源码**）。
- **`rcS` 里 source 的脚本是怎么进 ROMFS 的** → [01_extracted/nuttx/romfs](romfs.md)。
- **`rcS` 之后 module 层怎么协同** → [03_moc/03-module-map](../../03_moc/03-module-map.md)（task-11 负责）。
- **`param load-or-init` 读的那个 flash 扇区在哪** → [01_extracted/stm32/flash-layout](../stm32/flash-layout.md)。

---

## 未核实

- `apps/nshlib/Kconfig:878` 的默认值**为什么在 `.config` 里被显式写出来**（是 defaults 展开还是有人配过），未核实；
  我只确认了"板级 defconfig 里没有它、`.config` 里有它、`nsh.h` 有兜底"三件事。
- `nsh_consolemain()` 之后进入的是"读串口交互"还是"读某个已重定向的 fd"，本篇未展开（`nsh_consolemain.c` 未逐行读）。
- `rcS` 的行号我只**抽验**了 `:3`、`:58`、`:204`、`:420-424`、`:440`、`:446-449`、`:795-797`（全部命中）；
  其余行号来自既有素材 `work/PX4-rcS执行时序表.md`（其自称 109 行号已回验），**本篇未逐行复核**。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/modalai/voxl2/src/boardctl.c`
### `boards/rm2027/fmu-h743/nuttx-config/Kconfig`
### `boards/rm2027/fmu-h743/src/init.c`
<a id="src-boards-rm2027-fmu-h743-src-init-c-157"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:157`](nsh-and-rcS.md#^src-boards-rm2027-fmu-h743-src-init-c-157)

```c
   154 │  *   any failure to indicate the nature of the failure.
   155 │  *
   156 │  ****************************************************************************/
▶  157 │ __EXPORT int board_app_initialize(uintptr_t arg)
   158 │ {
   159 │ 	/* Need hrt running before using the ADC */
   160 │ 	px4_platform_init();
```
> **说明**：3a | → boardctl | nuttx/boards/boardctl.c:366 | case BOARDIOC_INIT: ⇒ 调 board_app_initialize() | ┃ 3b | → ③ 板级 | boards/rm2027/fmu-h743/src/init.c:157 | px4_platform_init()（:160）、DMA 分配器（:163）、LED（:168-170）、hardfault（:172-174）… |
^src-boards-rm2027-fmu-h743-src-init-c-157

### `platforms/nuttx/NuttX/apps/nshlib/nsh.h`
<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-299"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh.h:299`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-299)

```c
   296 │ #    define CONFIG_NSH_SYSINITSCRIPT "init.d/rc.sysinit"
   297 │ #  endif
   298 │ 
▶  299 │ #  ifndef CONFIG_NSH_INITSCRIPT
   300 │ #    define CONFIG_NSH_INITSCRIPT "init.d/rcS"
   301 │ #  endif
   302 │ 
```
> **说明**：所以"我没配它"≠"它没有值"。这也是改了它却看不到变化的原因（改板级 defconfig 是改不动的）。 ┃ 2. nsh.h:299 还有一层编译期兜底：即使 .config 里没有这个键，也会被 #ifndef 补成 "init.d/rcS"。
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-299

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-318"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh.h:318`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-318)

```c
   315 │ #    define NSH_RCPATH CONFIG_ETC_ROMFSMOUNTPT "/" CONFIG_NSH_RCSCRIPT
   316 │ #  endif
   317 │ 
▶  318 │ #else
   319 │ 
   320 │ #  undef CONFIG_NSH_ROMFSRC
   321 │ #  undef CONFIG_NSH_INITSCRIPT
```
> **说明**：2. nsh.h:299 还有一层编译期兜底：即使 .config 里没有这个键，也会被 #ifndef 补成 "init.d/rcS"。 ┃ 3. nsh.h:318 的 #else：如果没有 CONFIG_ETC_ROMFS，NSH_INITPATH 根本不存在、
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-h-318

### `platforms/nuttx/NuttX/apps/nshlib/nsh_init.c`
<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-106"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_init.c:106`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-106)

```c
   103 │  *
   104 │  ****************************************************************************/
   105 │ 
▶  106 │ void nsh_initialize(void)
   107 │ {
   108 │ #if defined (CONFIG_NSH_SYMTAB)
   109 │   struct boardioc_symtab_s symdesc;
```
> **说明**：1 | 新任务 nsh_main | apps/system/nsh/nsh_main.c:53（源文件里是 int main(...)，编译期被 -Dmain=nsh_main 改名） | :60-67 调优先级到 CONFIG_SYSTEM_NSH_PRIORITY（.config:2145 = 100） | ┃ 2 | nsh_main | :71 → apps/nshlib/nsh_init.c:106 | nsh_initialize()：设提示符（:117）、readline（:122）… |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-106

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-146"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_init.c:146`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-146)

```c
   143 │   boardctl(BOARDIOC_APP_SYMTAB, (uintptr_t)&symdesc);
   144 │ #endif
   145 │ 
▶  146 │ #ifdef CONFIG_NSH_ARCHINIT
   147 │   /* Perform architecture-specific initialization (if configured) */
   148 │ 
   149 │   boardctl(BOARDIOC_INIT, 0);
```
> **说明**：2 | nsh_main | :71 → apps/nshlib/nsh_init.c:106 | nsh_initialize()：设提示符（:117）、readline（:122）… | ┃ 3 | nsh_initialize | nsh_init.c:146 | CONFIG_NSH_ARCHINIT=y（.config:2106）⇒ boardctl(BOARDIOC_INIT, 0) |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-146

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-152"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_init.c:152`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-152)

```c
   149 │   boardctl(BOARDIOC_INIT, 0);
   150 │ #endif
   151 │ 
▶  152 │ #if defined(CONFIG_ETC_ROMFS) && !defined(CONFIG_NSH_DISABLESCRIPT)
   153 │   pstate = nsh_newconsole(false);
   154 │ 
   155 │   /* Execute the system init script */
```
> **说明**：3b | → ③ 板级 | boards/rm2027/fmu-h743/src/init.c:157 | px4_platform_init()（:160）、DMA 分配器（:163）、LED（:168-170）、hardfault（:172-174）… | ┃ 4 | nsh_initialize | nsh_init.c:152 | CONFIG_ETC_ROMFS 且未禁用脚本 ⇒ nsh_newconsole(false) + nsh_sysinitscript() |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-152

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-172"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_init.c:172`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-172)

```c
   169 │   boardctl(BOARDIOC_FINALINIT, 0);
   170 │ #endif
   171 │ 
▶  172 │ #if defined(CONFIG_ETC_ROMFS) && !defined(CONFIG_NSH_DISABLESCRIPT)
   173 │   /* Execute the start-up script */
   174 │ 
   175 │   nsh_initscript(&pstate->cn_vtbl);
```
> **说明**：4a | → nsh_script.c:215 | :221 | nsh_script_redirect(vtbl, "sysinit", NSH_SYSINITPATH, false) ⇒ 跑 /etc/init.d/rc.sysinit | ┃ 5 | nsh_initialize | nsh_init.c:172 | nsh_initscript() ⇒ nsh_script.c:237 ⇒ :253 nsh_script_redirect(vtbl, "init", NSH_INITPATH, true) |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-init-c-172

### `platforms/nuttx/NuttX/apps/nshlib/nsh_script.c`
<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-215"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_script.c:215`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-215)

```c
   212 │  ****************************************************************************/
   213 │ 
   214 │ #ifdef CONFIG_ETC_ROMFS
▶  215 │ int nsh_sysinitscript(FAR struct nsh_vtbl_s *vtbl)
   216 │ {
   217 │   /* Since most existing systems only use the NSH_INITPATH script file.
   218 │    * Do not log error output for a missing NSH_SYSINITPATH script file.
```
> **说明**：4 | nsh_initialize | nsh_init.c:152 | CONFIG_ETC_ROMFS 且未禁用脚本 ⇒ nsh_newconsole(false) + nsh_sysinitscript() | ┃ 4a | → nsh_script.c:215 | :221 | nsh_script_redirect(vtbl, "sysinit", NSH_SYSINITPATH, false) ⇒ 跑 /etc/init.d/rc.sysinit |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-215

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-221"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_script.c:221`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-221)

```c
   218 │    * Do not log error output for a missing NSH_SYSINITPATH script file.
   219 │    */
   220 │ 
▶  221 │   return nsh_script_redirect(vtbl, "sysinit", NSH_SYSINITPATH, false);
   222 │ }
   223 │ #endif
   224 │ 
```
> **说明**：rc.sysinit | /etc/init.d/rc.sysinit | nsh_script.c:221 传 false | 找不到不报错（:217-219 注释原话："Do not log error output for a missing … script file"） |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-221

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-236"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_script.c:236`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-236)

```c
   233 │  *
   234 │  ****************************************************************************/
   235 │ 
▶  236 │ #ifdef CONFIG_ETC_ROMFS
   237 │ int nsh_initscript(FAR struct nsh_vtbl_s *vtbl)
   238 │ {
   239 │   bool already;
```
> **说明**：3. nsh.h:318 的 #else：如果没有 CONFIG_ETC_ROMFS，NSH_INITPATH 根本不存在、 ┃ nsh_initscript() 也不会被编（nsh_script.c:236 的 #ifdef CONFIG_ETC_ROMFS）
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-236

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-237"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_script.c:237`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-237)

```c
   234 │  ****************************************************************************/
   235 │ 
   236 │ #ifdef CONFIG_ETC_ROMFS
▶  237 │ int nsh_initscript(FAR struct nsh_vtbl_s *vtbl)
   238 │ {
   239 │   bool already;
   240 │   int ret = OK;
```
> **说明**：4a | → nsh_script.c:215 | :221 | nsh_script_redirect(vtbl, "sysinit", NSH_SYSINITPATH, false) ⇒ 跑 /etc/init.d/rc.sysinit | ┃ 5 | nsh_initialize | nsh_init.c:172 | nsh_initscript() ⇒ nsh_script.c:237 ⇒ :253 nsh_script_redirect(vtbl, "init", NSH_INITPATH, true) |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-237

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-242"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_script.c:242`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-242)

```c
   239 │   bool already;
   240 │   int ret = OK;
   241 │ 
▶  242 │   /* Atomic test and set of the g_nsh_script_initialized flag */
   243 │ 
   244 │   sched_lock();
   245 │   already                  = g_nsh_script_initialized;
```
> **说明**：rcS | /etc/init.d/rcS | nsh_script.c:253 传 true | 找不到报错 | ┃ rcS 的幂等性 | — | nsh_script.c:242 | 用一个 g_nsh_script_initialized 标志 + sched_lock() 做"原子测试并置位" ⇒ 只会执行一次，重复调用无害 |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-242

<a id="src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-253"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/nshlib/nsh_script.c:253`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-253)

```c
   250 │ 
   251 │   if (!already)
   252 │     {
▶  253 │       ret = nsh_script_redirect(vtbl, "init", NSH_INITPATH, true);
   254 │ #ifndef CONFIG_NSH_DISABLESCRIPT
   255 │       /* Reset the option flags */
   256 │ 
```
> **说明**：rc.sysinit | /etc/init.d/rc.sysinit | nsh_script.c:221 传 false | 找不到不报错（:217-219 注释原话："Do not log error output for a missing … script file"） | ┃ rcS | /etc/init.d/rcS | nsh_script.c:253 传 true | 找不到报错 |
^src-platforms-nuttx-NuttX-apps-nshlib-nsh-script-c-253

### `platforms/nuttx/NuttX/apps/system/nsh/nsh_main.c`
<a id="src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-53"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/system/nsh/nsh_main.c:53`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-53)

```c
    50 │  *
    51 │  ****************************************************************************/
    52 │ 
▶   53 │ int main(int argc, FAR char *argv[])
    54 │ {
    55 │   struct sched_param param;
    56 │   int ret = 0;
```
> **说明**：1 | 新任务 nsh_main | apps/system/nsh/nsh_main.c:53（源文件里是 int main(...)，编译期被 -Dmain=nsh_main 改名） | :60-67 调优先级到 CONFIG_SYSTEM_NSH_PRIORITY（.config:2145 = 100） |
^src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-53

<a id="src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-76"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/system/nsh/nsh_main.c:76`](nsh-and-rcS.md#^src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-76)

```c
    73 │ #ifdef CONFIG_NSH_CONSOLE
    74 │   /* If the serial console front end is selected, run it on this thread */
    75 │ 
▶   76 │   ret = nsh_consolemain(argc, argv);
    77 │ 
    78 │   /* nsh_consolemain() should not return.  So if we get here, something
    79 │    * is wrong.
```
> **说明**：5 | nsh_initialize | nsh_init.c:172 | nsh_initscript() ⇒ nsh_script.c:237 ⇒ :253 nsh_script_redirect(vtbl, "init", NSH_INITPATH, true) | ┃ 6 | nsh_main | nsh_main.c:76 | nsh_consolemain(argc, argv) ⇒ NSH 交互控制台（:78-83 注释原话：*"should not return"*） |
^src-platforms-nuttx-NuttX-apps-system-nsh-nsh-main-c-76
