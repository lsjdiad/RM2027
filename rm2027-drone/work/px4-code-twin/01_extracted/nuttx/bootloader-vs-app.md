# bootloader 构建 vs app 构建：**同一份 NuttX，两个配置**

> **层**：01 提炼知识
> **用途**：解释"为什么同一块板子上，bootloader 和应用看起来像两个完全不同的系统"
> **依据**：两个构建产物目录
> `build/rm2027_fmu-h743_bootloader/NuttX/nuttx/.config` 与 `build/rm2027_fmu-h743_default/NuttX/nuttx/.config`

---

## 1. 一句话

**板级目录 `boards/rm2027/fmu-h743/` 是同一份；分出两个系统的是两个 `.px4board` 文件 + 两个 NuttX defconfig。**

| | bootloader | app |
|---|---|---|
| 触发文件 | `boards/rm2027/fmu-h743/bootloader.px4board`（**3 行**） | `boards/rm2027/fmu-h743/default.px4board` |
| `PX4_BOARD_LABEL` | `bootloader`（[`CMakeCache.txt:319`](bootloader-vs-app.md#^src-build-px4-sitl-default-CMakeCache-txt-319)） | `default` |
| NuttX defconfig | `nuttx-config/bootloader/defconfig`（78 行） | `nuttx-config/nsh/defconfig`（数百行） |
| linker script | `nuttx-config/scripts/bootloader_script.ld`（flash **128 KiB**） | `nuttx-config/scripts/script.ld`（flash **1792 KiB**） |
| 镜像基址 | `0x08000000` | `0x08020000` |
| 产物 | `extras/rm2027_fmu-h743_bootloader.bin` | `rm2027_fmu-h743_default.px4` |

`bootloader.px4board` 全文只有 3 行（`:1-3`）：工具链、架构、`CONFIG_BOARD_ROMFSROOT=""`。
**⇒ 板级"身份"（`hw_config.h` 里的 BOARD_TYPE=2027、APP_LOAD_ADDRESS…）两个构建共用同一份头文件。**

---

## 2. 配置差异对照表（都是可查的）

| 配置键 | bootloader | app | 影响什么 |
|---|---|---|---|
| `CONFIG_INIT_ENTRYPOINT` | `"bootloader_main"`（`.config:601`） | `"nsh_main"`（`.config:707`） | ★ **控制权交给谁** |
| `CONFIG_BOARD_LATE_INITIALIZE` | **`y`**（`.config:648`） | **`is not set`**（`.config:789`） | ★ 是否新建 `AppBringUp` 线程；`board_late_initialize()` 会不会被调 |
| `CONFIG_ETC_ROMFS` | **`is not set`** ⇒ `# CONFIG_FS_ROMFS is not set`（`.config:1024`） | **`y`**（`.config:709`） | ★ 有没有 `/etc`、有没有 `rcS` |
| `CONFIG_ETC_CROMFS` | n/a | `y`（`.config:710`） | 用 cromfs 后端（压缩只读）挂 `/etc` |
| `CONFIG_ETC_ROMFSMOUNTPT` | n/a | `"/etc"`（`.config:711`） | `NSH_INITPATH` 的前缀 |
| `CONFIG_NSH_LIBRARY` | `is not set`（`.config:1616`） | `y`（`.config:1980`） | 有没有 shell |
| `CONFIG_NSH_INITSCRIPT` | n/a | `"init.d/rcS"`（`.config:2095`） | ★ 启动脚本名 |
| `CONFIG_NSH_SYSINITSCRIPT` | n/a | `"init.d/rc.sysinit"`（`.config:2094`） | 前置脚本名 |
| `CONFIG_NSH_ARCHINIT` | n/a | `y`（`.config:2106`） | ★ 是否 `boardctl(BOARDIOC_INIT)` ⇒ 是否调 `board_app_initialize()` |
| `CONFIG_SYSTEM_NSH` | `is not set`（`.config:1644`） | `y`（`.config:2144`） | 有没有 NSH 这个 app |
| `CONFIG_SYSTEMTICK_HOOK` | **`y`**（`.config:578`） | **`is not set`**（`.config:684`） | ★ 只有 bootloader 需要 `board_timerhook()` |
| `CONFIG_USBDEV` | `is not set`（`.config:888`） | （app 侧另有 USB 配置） | 决定 `sercon_main` 能否真的做事 |
| `CONFIG_NO_SERIAL_CONSOLE` | `y`（`.config:870`） | — | ★ bootloader **没有控制台**（所以 `printf` 打不出来） |
| `CONFIG_ARCH_INTERRUPTSTACK` | `768`（`.config:485`） | 同 | >7 ⇒ 线程模式跑 PSP ⇒ 跳转时必须切回 MSP（[`main.c:646`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646)） |

**⇒ 一句话总结这些差异**：
`CONFIG_INIT_ENTRYPOINT` 决定**去哪**，`CONFIG_BOARD_LATE_INITIALIZE` 决定**在哪条线程上初始化**，
`CONFIG_ETC_ROMFS` + `CONFIG_NSH_*` 决定**有没有 shell 和脚本**，`CONFIG_SYSTEMTICK_HOOK` 决定**bootloader 的时间从哪来**。

---

## 3. 执行序对照（同一条 `__start`，分叉在 `nx_bringup`）

```
                       __start (stm32_start.c:183)
                            │  ← 两份构建完全相同
                            ├─ stm32_boardinitialize()   :262
                            │      bl  → bootloader_main.c:55（空）
                            │      app → init.c:120（GPIO/SPI/LED/PWM 复位）
                            ├─ nx_start()                :315
                            ├─ irq_initialize()/up_initialize()
                            └─ nx_bringup()              nx_start.c:743
                                 ├─ nx_workqueues()      nx_bringup.c:530
                                 └─ nx_create_initthread() :537
                                      ├─ bl ：CONFIG_BOARD_LATE_INITIALIZE=y
                                      │      → nxthread_create("AppBringUp", nx_start_task)  :443
                                      │         └─ nx_start_application() :412
                                      │              ├─ （无 ROMFS ⇒ 跳过 nx_romfsetc）  :313
                                      │              ├─ board_late_initialize() → sercon_main()  :321
                                      │              └─ task_spawn("bootloader_main")  :356
                                      │                   └─ ★ bootloader 主函数  main.c:660
                                      └─ app：CONFIG_BOARD_LATE_INITIALIZE is not set
                                             → nx_start_application() 直接执行  :452
                                                  ├─ nx_romfsetc() 挂 /etc  :313
                                                  └─ task_spawn("nsh_main")  :356
                                                       └─ ★ nsh  main  apps/system/nsh/nsh_main.c:53
```

**⇒ 两条路在 `nx_create_initthread()`（[`nx_bringup.c:434`](bootloader-vs-app.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-434)）之后**才**分开，前面完全一样。**
这条"前同后异"的结构是理解整个系统启动的关键。

---

## 4. 对本板台架的直接后果

| 观察 | 为什么 |
|---|---|
| bootloader 串口上**打不出任何字** | bl `.config:870 CONFIG_NO_SERIAL_CONSOLE=y`；且 ①层本身无 `printf` |
| app 串口上**能看到 `INFO [init] …`** | app 有 NSH + ROMFS + `rcS` 里那一堆 `echo` |
| bootloader 的"超时"能走 | bl `.config:578 CONFIG_SYSTEMTICK_HOOK=y` ⇒ `board_timerhook()` |
| app 里 `board_timerhook()` 不会被调 | app `.config:684 is not set`；也不需要（app 有自己的 hrt） |
| 改 `hw_config.h` 两个构建**都会变** | 同一个 `-I.../boards/rm2027/fmu-h743/src`（`compile_commands.json` 已核实） |
| `extras/*_bootloader.bin` 是"产物 + app 构建的输入" | [`platforms/nuttx/CMakeLists.txt:523`](bootloader-vs-app.md#^src-platforms-nuttx-CMakeLists-txt-523)（产出）/ `:539-546`（包成 elf） |

---

## 跳转

- **下一步（app 侧）**：`nsh_main` 之后发生什么 → [01_extracted/nuttx/nsh-and-rcS](nsh-and-rcS.md)。
- **下一步（bootloader 侧）**：`bootloader_main` 之后发生什么 → [02_code_twin/bootloader/stm32-common-main-c](../../02_code_twin/bootloader/stm32-common-main-c.md)。
- **`nx_romfsetc()` 怎么挂 `/etc`、rcS 怎么进去的** → [01_extracted/nuttx/romfs](romfs.md)。
- **整条内核启动链（含 `__start` 的时钟/外设）** → [01_extracted/nuttx/00-poweron-chain](00-poweron-chain.md) / [01_extracted/stm32/00-reset-clock-peripherals](../stm32/00-reset-clock-peripherals.md)。
- **两个 linker script 的 flash 布局** → [01_extracted/stm32/flash-layout](../stm32/flash-layout.md)。

---

## 未核实

- app 侧 `CONFIG_USBDEV` 的取值我没查（与 bootloader 篇无关）。
- app 的 `default.px4board` 全文我只读了前 20 行（见 [02_code_twin/board](../../02_code_twin/board/README.md)，task-12 负责）；
  本篇只用它证明"两个构建来自两个 `.px4board`"。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `build/px4_sitl_default/CMakeCache.txt`
<a id="src-build-px4-sitl-default-CMakeCache-txt-319"></a>
**↓ 文档在讲这里：**[`build/px4_sitl_default/CMakeCache.txt:319`](bootloader-vs-app.md#^src-build-px4-sitl-default-CMakeCache-txt-319)

```c
   316 │ // but are added when building.
   317 │ CMAKE_SKIP_INSTALL_RPATH:BOOL=NO
   318 │ 
▶  319 │ //If set, runtime paths are not added when using shared libraries.
   320 │ CMAKE_SKIP_RPATH:BOOL=NO
   321 │ 
   322 │ //Flags used by the linker during the creation of static libraries
```
> **说明**：触发文件 | boards/rm2027/fmu-h743/bootloader.px4board（3 行） | boards/rm2027/fmu-h743/default.px4board | ┃ PX4_BOARD_LABEL | bootloader（CMakeCache.txt:319） | default |
^src-build-px4-sitl-default-CMakeCache-txt-319

### `platforms/nuttx/CMakeLists.txt`
<a id="src-platforms-nuttx-CMakeLists-txt-523"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:523`](bootloader-vs-app.md#^src-platforms-nuttx-CMakeLists-txt-523)

```c
   520 │ endif()
   521 │ 
   522 │ if("${PX4_BOARD_LABEL}" STREQUAL "bootloader")
▶  523 │ 	add_custom_command(OUTPUT ${PX4_BOARD_DIR}/extras/${PX4_BOARD}_bootloader.bin
   524 │ 		COMMAND ${CMAKE_OBJCOPY} -O binary ${PX4_BINARY_DIR_REL}/${FW_NAME} ${PX4_BOARD_DIR}/extras/${PX4_BOARD}_bootloader.bin
   525 │ 		DEPENDS px4
   526 │ 	)
```
> **说明**：改 hw_config.h 两个构建都会变 | 同一个 -I.../boards/rm2027/fmu-h743/src（compile_commands.json 已核实） | ┃ extras/*_bootloader.bin 是"产物 + app 构建的输入" | platforms/nuttx/CMakeLists.txt:523（产出）/ :539-546（包成 elf） |
^src-platforms-nuttx-CMakeLists-txt-523

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-434"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:434`](bootloader-vs-app.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-434)

```c
   431 │  *
   432 │  ****************************************************************************/
   433 │ 
▶  434 │ static inline void nx_create_initthread(void)
   435 │ {
   436 │ #ifdef CONFIG_BOARD_LATE_INITIALIZE
   437 │   int pid;
```
> **说明**：⇒ 两条路在 nx_create_initthread()（nx_bringup.c:434）之后才分开，前面完全一样。
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-434

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:646`](bootloader-vs-app.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646)

```c
   643 │ 	 * on the MSP, so select it again before handing over -- otherwise the app
   644 │ 	 * keeps running on the bootloader's stack and faults once it is clobbered.
   645 │ 	 */
▶  646 │ 	asm volatile(
   647 │ 		"mrs %0, control  \n"
   648 │ 		"bic %0, %0, #2   \n"
   649 │ 		"msr control, %0  \n"
```
> **说明**：CONFIG_NO_SERIAL_CONSOLE | y（.config:870） | — | ★ bootloader 没有控制台（所以 printf 打不出来） | ┃ CONFIG_ARCH_INTERRUPTSTACK | 768（.config:485） | 同 | >7 ⇒ 线程模式跑 PSP ⇒ 跳转时必须切回 MSP（main.c:646） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:660`](bootloader-vs-app.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660)

```c
   657 │ }
   658 │ 
   659 │ int
▶  660 │ bootloader_main(int argc, char *argv[])
   661 │ {
   662 │ 	bool try_boot = true;			/* try booting before we drop to the bootloader */
   663 │ 	unsigned timeout = BOOTLOADER_DELAY;	/* if nonzero, drop out of the bootloader after this time */
```
> **说明**：│ └─ ★ bootloader 主函数 main.c:660
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660
