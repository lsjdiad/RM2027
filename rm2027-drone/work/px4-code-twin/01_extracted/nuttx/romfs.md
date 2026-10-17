# ROMFS：`rcS` 是怎么变成镜像的一部分的

> **层**：01 提炼知识
> **素材**：`ROMFS/CMakeLists.txt`（480+ 行）、`platforms/nuttx/CMakeLists.txt:191-193/340-342/394-396`、
> `nuttx/sched/init/nx_bringup.c:126-133/243-278`、`nuttx/tools/gencromfs.c`、`nuttx/fs/cromfs/fs_cromfs.c:231/1442-1446`
> **一句话**：**`/etc` 不是一个分区，是一段编译进 `.rodata` 的字节数组。**

---

## 1. 构建期：从源码树到 `nsh_romfsimg.c`（6 步）

| # | 位置 | 干什么 |
|---|---|---|
| 1 | [`ROMFS/CMakeLists.txt:74`](romfs.md#^src-ROMFS-CMakeLists-txt-74) `add_subdirectory(${romfs_src_dir})` | 进 `ROMFS/px4fmu_common/`（再 [`ROMFS/px4fmu_common/CMakeLists.txt:34`](romfs.md#^src-ROMFS-px4fmu-common-CMakeLists-txt-34) 进 `init.d/`） |
| 2 | `ROMFS/CMakeLists.txt:62-71 px4_add_romfs_files()` | 每个子目录 CMakeLists 用它把脚本登记进全局属性 `PX4_ROMFS_FILES`（`:69`） |
| 3 | [`ROMFS/CMakeLists.txt:119`](romfs.md#^src-ROMFS-CMakeLists-txt-119) | 把登记到的文件**打成 `romfs_files.tar`**（`:122`） |
| 4 | [`ROMFS/CMakeLists.txt:140`](romfs.md#^src-ROMFS-CMakeLists-txt-140) | 解到 `build/<board>/etc/`（`:148`），然后跑三个生成器：`px_process_airframes.py`（`:149`）、`Tools/serial/generate_config.py`（`:153`，产 **`rc.serial`**）、`Tools/filepaths/generate_config.py`（`:157`，产 **`rc.filepaths`**） |
| 5 | [`ROMFS/CMakeLists.txt:194`](romfs.md#^src-ROMFS-CMakeLists-txt-194) | ★ **把 ③ 层 `boards/rm2027/fmu-h743/init/rc.board_*` 拷进去**——但**只认白名单 5 个名字**（`:196-202`：`rc.board_early` / `rc.board_defaults` / `rc.board_sensors` / `rc.board_extras` / `rc.board_mavlink`），且必须 `EXISTS`（`:206`） |
| 5b | [`ROMFS/CMakeLists.txt:255`](romfs.md#^src-ROMFS-CMakeLists-txt-255) | 把 `boards/rm2027/fmu-h743/extras/*` 拷到 `/etc/extras/`（`:309`）⇒ **bootloader 的 `.bin` 走这条** |
| 6 | [`ROMFS/CMakeLists.txt:401`](romfs.md#^src-ROMFS-CMakeLists-txt-401) | `Tools/px_romfs_pruner.py` **裁剪**（去注释/空行）—— `rcS:14` 那句"COMMENT LINES ARE REMOVED"说的就是这一步 |
| 7 | [`ROMFS/CMakeLists.txt:412`](romfs.md#^src-ROMFS-CMakeLists-txt-412)（cromfs 分支） | 编 host 工具 `gencromfs`（`:415`）→ **`gencromfs <build>/etc nsh_romfsimg.c`**（`:424`）→ `add_library(romfs STATIC nsh_romfsimg.c)`（`:431`） |
| 8 | [`platforms/nuttx/CMakeLists.txt:394`](../../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-394) | `target_link_libraries(px4 PRIVATE romfs)` ⇒ **数组被链进固件** |

**本板实测**（`build/rm2027_fmu-h743_default/`）：
- `etc/init.d/` 里 **25 个文件**，其中包含本板的 `rc.board_defaults` / `rc.board_sensors` / `rc.board_extras`
  与平台级的 `rc.board_arch_defaults`；
- `ROMFS/nsh_romfsimg.c` 生成成功，**806,054 字节**（≈ 787 KiB 源码，含已压缩的镜像数组）。

---

## 2. 生成的数组长什么样（关键：符号名不是 `romfs_img`）

```
build/rm2027_fmu-h743_default/ROMFS/nsh_romfsimg.c:33
const uint8_t aligned_data(4) g_cromfs_image[] =
```

[`gencromfs.c:1315`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-1315) 就是这一行的出处。

**⇒ `CONFIG_ETC_CROMFS=y` 时用的是 `g_cromfs_image`，而 [`nx_bringup.c:131`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-131) 里声明的
`romfs_img` / `romfs_img_len` **不被使用**（那两条只在普通 romfs 分支用）。**
这是个容易找错符号的地方。

**cromfs 是"文件系统类型"，不是块设备**：
- [`nuttx/fs/cromfs/fs_cromfs.c:231`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-fs-cromfs-fs-cromfs-c-231) 直接 `extern const struct cromfs_volume_s g_cromfs_image;`
- `:1442-1446` 在 `bind()` 里 `DEBUGASSERT(g_cromfs_image.cv_magic == CROMFS_MAGIC)` 后 `*handle = &g_cromfs_image`
- ⇒ [`nx_bringup.c:128`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-128) 里的 `MOUNT_DEVNAME = "/dev/ram0"` **只是个形式参数**，没有真的块设备。

---

## 3. 运行期：`/etc` 是怎么被挂上的

```
nx_bringup.c:313   #ifdef CONFIG_ETC_ROMFS
                   nx_romfsetc();          ← nx_start_application() 进入用户任务之前
nx_bringup.c:244   static inline void nx_romfsetc(void)
nx_bringup.c:248-259   #ifndef CONFIG_ETC_CROMFS → romdisk_register(romfs_img, …, CONFIG_ETC_ROMFSSECTSIZE)
nx_bringup.c:266-272   #if defined(CONFIG_ETC_CROMFS)
                            nx_mount(MOUNT_DEVNAME, CONFIG_ETC_ROMFSMOUNTPT, "cromfs", MS_RDONLY, NULL);
```

**本板（app）取值**：`CONFIG_ETC_CROMFS=y`（`.config:710`）、
`CONFIG_ETC_ROMFSMOUNTPT="/etc"`（`.config:711`）、`CONFIG_ETC_ROMFSDEVNO=0`（`:712`）
⇒ 执行的是 `:267-268` 的 cromfs 分支，挂载点 `/etc`。

**⇒ 之后 `NSH_INITPATH = "/etc" "/" "init.d/rcS"` 才存在**（见 [01_extracted/nuttx/nsh-and-rcS](nsh-and-rcS.md) §2）。

---

## 4. ★ 三条最容易踩的结论

1. **脚本改了必须重新编译**。ROMFS 是**编译期数组**，不是盘上文件 ⇒
   在板上 `vi /etc/init.d/rcS` 即使能写，重启也没了（而且是只读挂载 `MS_RDONLY`）。
2. **③层钩子脚本"看不见"= 构建期问题**。`rcS:421-424` 是 `if [ -f $BOARD_RC_SENSORS ]`；
   文件没进 ROMFS 的**唯一原因**是**不满足 `:196-202` 的 5 个文件名白名单**或不在 `init/` 下。
   **不是脚本内容问题**。
3. **`rcS` 的行号会因裁剪而变**（`:401-410`）⇒ 做行号核对时基准必须是**源码树里的 `rcS`**，
   不是 `build/<board>/etc/init.d/rcS`。

### 4.1 bootloader 构建为什么没有 ROMFS

| 环节 | bootloader | app |
|---|---|---|
| [`bootloader.px4board:3`](romfs.md#^src-boards-rm2027-fmu-h743-bootloader-px4board-3) | `CONFIG_BOARD_ROMFSROOT=""` | `default.px4board` 里为 `px4fmu_common` |
| ⇒ CMake 变量 | `config_romfs_root` 为空 | 非空 |
| ⇒ [`platforms/nuttx/CMakeLists.txt:191`](romfs.md#^src-platforms-nuttx-CMakeLists-txt-191) 的 `if (config_romfs_root)` | **假** ⇒ 不 `add_subdirectory(ROMFS)`、不链 `romfs` | 真 ⇒ 链 `romfs` |
| ⇒ NuttX `.config` | `# CONFIG_FS_ROMFS is not set`（`.config:1024`） | `CONFIG_ETC_ROMFS=y`（`:709`） |
| ⇒ 运行期 | `nx_romfsetc()` 整段被 `#ifdef CONFIG_ETC_ROMFS` 裁掉 | 挂 `/etc` |
| ⇒ 后果 | **bootloader 里没有 `/etc`、没有 `rcS`、没有 shell**；它的 `/dev/ttyS0` 来自 NuttX 编译期注册的驱动 | 有 shell、有脚本 |

**⇒ 这就是"为什么 bootloader 看起来完全不像一个 Linux 系统"的根本原因：它连文件系统都没有。**

---

## 5. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| 改 `boards/rm2027/fmu-h743/init/rc.board_sensors` 后**没生效** | 没重新编译 ⇒ ROMFS 未重建 | [`ROMFS/CMakeLists.txt:422`](romfs.md#^src-ROMFS-CMakeLists-txt-422) |
| 脚本名字改对了但**还是没进** | 白名单 5 个名 | [`ROMFS/CMakeLists.txt:196`](romfs.md#^src-ROMFS-CMakeLists-txt-196) |
| 串口打出的 `rcS` 行号与源码树对不上 | `px_romfs_pruner.py` 去注释 | [`ROMFS/CMakeLists.txt:401`](romfs.md#^src-ROMFS-CMakeLists-txt-401) + `rcS:14` |
| 固件体积比预期大很多 | ROMFS 数组直接进 `.rodata` | [`nsh_romfsimg.c:33`](romfs.md#^src-build-rm2027-fmu-h743-default-ROMFS-nsh-romfsimg-c-33) |
| `rc.serial` / `rc.autostart` / `rc.filepaths` 在源码树里**找不到** | 它们是**构建期生成**的 | [`ROMFS/CMakeLists.txt:142`](romfs.md#^src-ROMFS-CMakeLists-txt-142)、`:153-161` |
| bootloader 里 `/etc` 不存在 | `CONFIG_BOARD_ROMFSROOT=""` | [`bootloader.px4board:3`](romfs.md#^src-boards-rm2027-fmu-h743-bootloader-px4board-3) |

---

## 跳转

- **执行序上一步**（谁调 `nx_romfsetc()`）→ [01_extracted/nuttx/00-poweron-chain](00-poweron-chain.md) 第 14 步。
- **执行序下一步**（挂完 `/etc` 之后谁去读 `/etc/init.d/rcS`）→ [01_extracted/nuttx/nsh-and-rcS](nsh-and-rcS.md)。
- **两个构建的完整差异表** → [01_extracted/nuttx/bootloader-vs-app](bootloader-vs-app.md)。
- **`rcS` 里各阶段干什么** → 既有素材 `work/PX4-rcS执行时序表.md`。
- **③层 25 个文件里哪几个走"进 ROMFS"这条路** → [02_code_twin/board](../../02_code_twin/board/README.md)（task-12 负责）。

---

## 未核实

- `Tools/px_romfs_pruner.py` 的**具体裁剪规则**（去注释？压缩？）我**没有读**该脚本；
  只说"它改变了最终镜像里的行结构"，依据是 [`ROMFS/CMakeLists.txt:401`](romfs.md#^src-ROMFS-CMakeLists-txt-401) 的调用 + `rcS:14` 的注释。
- `gencromfs` 的**压缩算法（LZF）与解压时机**未展开（[`gencromfs.c:170`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-170) 有 `lzf_len` 字段，未深读）。
- `config_romfs_root` 这个 CMake 变量从 `CONFIG_BOARD_ROMFSROOT` 到 [`CMakeLists.txt:191`](romfs.md#^src-CMakeLists-txt-191) 的完整传递链
  属 [03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)（task-10）范围，本篇只用到结论。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-191"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:191`](romfs.md#^src-CMakeLists-txt-191)

```c
   188 │ # line, or from the top Makefile); or else default to what
   189 │ # find_package(Python3) resolved. Promote to a CACHE FILEPATH entry so
   190 │ # cmake -L lists it, to avoid spurious reconfiguration.
▶  191 │ if(NOT DEFINED PYTHON_EXECUTABLE OR PYTHON_EXECUTABLE STREQUAL "")
   192 │ 	set(PYTHON_EXECUTABLE "${Python3_EXECUTABLE}")
   193 │ endif()
   194 │ set(PYTHON_EXECUTABLE "${PYTHON_EXECUTABLE}" CACHE FILEPATH "Python 3 interpreter" FORCE)
```
> **说明**：gencromfs 的压缩算法（LZF）与解压时机未展开（gencromfs.c:170 有 lzf_len 字段，未深读）。 ┃ config_romfs_root 这个 CMake 变量从 CONFIG_BOARD_ROMFSROOT 到 CMakeLists.txt:191 的完整传递链
^src-CMakeLists-txt-191

### `ROMFS/CMakeLists.txt`
<a id="src-ROMFS-CMakeLists-txt-74"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:74`](romfs.md#^src-ROMFS-CMakeLists-txt-74)

```c
    71 │ endfunction()
    72 │ 
    73 │ # get list of all ROMFS files
▶   74 │ add_subdirectory(${romfs_src_dir})
    75 │ 
    76 │ # directory setup
    77 │ # copy all romfs files, process airframes
```
> **说明**：1 | ROMFS/CMakeLists.txt:74 add_subdirectory(${romfs_src_dir}) | 进 ROMFS/px4fmu_common/（再 ROMFS/px4fmu_common/CMakeLists.txt:34 进 init.d/） |
^src-ROMFS-CMakeLists-txt-74

<a id="src-ROMFS-CMakeLists-txt-119"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:119`](romfs.md#^src-ROMFS-CMakeLists-txt-119)

```c
   116 │ # copy the ROMFS files by creating a tar and extracting it to the build
   117 │ # directory (which preserves the directory structure)
   118 │ file(MAKE_DIRECTORY ${romfs_gen_root_dir})
▶  119 │ set(romfs_tar_file ${PX4_BINARY_DIR}/romfs_files.tar)
   120 │ add_custom_command(
   121 │ 	OUTPUT ${romfs_tar_file}
   122 │ 	COMMAND ${CMAKE_COMMAND} -E tar cf ${romfs_tar_file} ${romfs_copy_files_relative}
```
> **说明**：2 | ROMFS/CMakeLists.txt:62-71 px4_add_romfs_files() | 每个子目录 CMakeLists 用它把脚本登记进全局属性 PX4_ROMFS_FILES（:69） | ┃ 3 | ROMFS/CMakeLists.txt:119 | 把登记到的文件打成 romfs_files.tar（:122） |
^src-ROMFS-CMakeLists-txt-119

<a id="src-ROMFS-CMakeLists-txt-140"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:140`](romfs.md#^src-ROMFS-CMakeLists-txt-140)

```c
   137 │ 
   138 │ 
   139 │ set(romfs_copy_stamp ${CMAKE_CURRENT_BINARY_DIR}/romfs_copy.stamp)
▶  140 │ add_custom_command(
   141 │ 	OUTPUT
   142 │ 		${romfs_gen_root_dir}/init.d/rc.serial
   143 │ 		${romfs_gen_root_dir}/init.d/rc.autostart
```
> **说明**：3 | ROMFS/CMakeLists.txt:119 | 把登记到的文件打成 romfs_files.tar（:122） | ┃ 4 | ROMFS/CMakeLists.txt:140 | 解到 build/<board>/etc/（:148），然后跑三个生成器：px_process_airframes.py（:149）、Tools/serial/generate_config.py（:153，产 rc.serial）、Tools/filepaths/generate_config.py（:157，产 rc.filepat
^src-ROMFS-CMakeLists-txt-140

<a id="src-ROMFS-CMakeLists-txt-142"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:142`](romfs.md#^src-ROMFS-CMakeLists-txt-142)

```c
   139 │ set(romfs_copy_stamp ${CMAKE_CURRENT_BINARY_DIR}/romfs_copy.stamp)
   140 │ add_custom_command(
   141 │ 	OUTPUT
▶  142 │ 		${romfs_gen_root_dir}/init.d/rc.serial
   143 │ 		${romfs_gen_root_dir}/init.d/rc.autostart
   144 │ 		${romfs_gen_root_dir}/init.d/rc.autostart.post
   145 │ 		${romfs_gen_root_dir}/init.d/rc.filepaths
```
> **说明**：固件体积比预期大很多 | ROMFS 数组直接进 .rodata | nsh_romfsimg.c:33 | ┃ rc.serial / rc.autostart / rc.filepaths 在源码树里找不到 | 它们是构建期生成的 | ROMFS/CMakeLists.txt:142、:153-161 |
^src-ROMFS-CMakeLists-txt-142

<a id="src-ROMFS-CMakeLists-txt-194"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:194`](romfs.md#^src-ROMFS-CMakeLists-txt-194)

```c
   191 │ endif()
   192 │ 
   193 │ 
▶  194 │ # board custom init files
   195 │ set(OPTIONAL_BOARD_RC)
   196 │ list(APPEND OPTIONAL_BOARD_RC
   197 │ 	rc.board_early
```
> **说明**：4 | ROMFS/CMakeLists.txt:140 | 解到 build/<board>/etc/（:148），然后跑三个生成器：px_process_airframes.py（:149）、Tools/serial/generate_config.py（:153，产 rc.serial）、Tools/filepaths/generate_config.py（:157，产 rc.filepat ┃ 5 | ROMFS/CMakeLists.txt:194 | ★ 把 ③ 层 boards/rm2027/fmu-h743/init/rc.board_* 拷进去——但只认白名单 5 个名字（:196-202：rc.board_early / rc.board_defaults / rc.board_sensors / rc.board_extras / rc.board_mavlink），且必须
^src-ROMFS-CMakeLists-txt-194

<a id="src-ROMFS-CMakeLists-txt-196"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:196`](romfs.md#^src-ROMFS-CMakeLists-txt-196)

```c
   193 │ 
   194 │ # board custom init files
   195 │ set(OPTIONAL_BOARD_RC)
▶  196 │ list(APPEND OPTIONAL_BOARD_RC
   197 │ 	rc.board_early
   198 │ 	rc.board_defaults
   199 │ 	rc.board_sensors
```
> **说明**：改 boards/rm2027/fmu-h743/init/rc.board_sensors 后没生效 | 没重新编译 ⇒ ROMFS 未重建 | ROMFS/CMakeLists.txt:422 | ┃ 脚本名字改对了但还是没进 | 白名单 5 个名 | ROMFS/CMakeLists.txt:196 |
^src-ROMFS-CMakeLists-txt-196

<a id="src-ROMFS-CMakeLists-txt-255"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:255`](romfs.md#^src-ROMFS-CMakeLists-txt-255)

```c
   252 │ endif()
   253 │ 
   254 │ 
▶  255 │ # board extras
   256 │ set(OPTIONAL_BOARD_EXTRAS)
   257 │ file(GLOB OPTIONAL_BOARD_EXTRAS ${PX4_BOARD_DIR}/extras/*)
   258 │ 
```
> **说明**：5 | ROMFS/CMakeLists.txt:194 | ★ 把 ③ 层 boards/rm2027/fmu-h743/init/rc.board_* 拷进去——但只认白名单 5 个名字（:196-202：rc.board_early / rc.board_defaults / rc.board_sensors / rc.board_extras / rc.board_mavlink），且必须 ┃ 5b | ROMFS/CMakeLists.txt:255 | 把 boards/rm2027/fmu-h743/extras/* 拷到 /etc/extras/（:309）⇒ bootloader 的 .bin 走这条 |
^src-ROMFS-CMakeLists-txt-255

<a id="src-ROMFS-CMakeLists-txt-401"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:401`](romfs.md#^src-ROMFS-CMakeLists-txt-401)

```c
   398 │ 		romfs_extras.stamp
   399 │ 	)
   400 │ 
▶  401 │ add_custom_command(
   402 │ 	OUTPUT romfs_pruned.stamp
   403 │ 	COMMAND ${PYTHON_EXECUTABLE} ${PX4_SOURCE_DIR}/Tools/px_romfs_pruner.py --folder ${romfs_gen_root_dir} --board ${PX4_BOARD}
   404 │ 	COMMAND ${CMAKE_COMMAND} -E touch romfs_pruned.stamp
```
> **说明**：5b | ROMFS/CMakeLists.txt:255 | 把 boards/rm2027/fmu-h743/extras/* 拷到 /etc/extras/（:309）⇒ bootloader 的 .bin 走这条 | ┃ 6 | ROMFS/CMakeLists.txt:401 | Tools/px_romfs_pruner.py 裁剪（去注释/空行）—— rcS:14 那句"COMMENT LINES ARE REMOVED"说的就是这一步 |
> **说明**：脚本名字改对了但还是没进 | 白名单 5 个名 | ROMFS/CMakeLists.txt:196 | ┃ 串口打出的 rcS 行号与源码树对不上 | px_romfs_pruner.py 去注释 | ROMFS/CMakeLists.txt:401 + rcS:14 |
^src-ROMFS-CMakeLists-txt-401

<a id="src-ROMFS-CMakeLists-txt-412"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:412`](romfs.md#^src-ROMFS-CMakeLists-txt-412)

```c
   409 │ 	COMMENT "ROMFS: pruning"
   410 │ 	)
   411 │ 
▶  412 │ if("${CONFIG_FS_CROMFS}" STREQUAL "y")
   413 │ 	add_custom_command(
   414 │ 		OUTPUT ${CMAKE_BINARY_DIR}/gencromfs
   415 │ 		COMMAND make --no-print-directory --silent -f Makefile.host gencromfs
```
> **说明**：6 | ROMFS/CMakeLists.txt:401 | Tools/px_romfs_pruner.py 裁剪（去注释/空行）—— rcS:14 那句"COMMENT LINES ARE REMOVED"说的就是这一步 | ┃ 7 | ROMFS/CMakeLists.txt:412（cromfs 分支） | 编 host 工具 gencromfs（:415）→ gencromfs <build>/etc nsh_romfsimg.c（:424）→ add_library(romfs STATIC nsh_romfsimg.c)（:431） |
^src-ROMFS-CMakeLists-txt-412

<a id="src-ROMFS-CMakeLists-txt-422"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:422`](romfs.md#^src-ROMFS-CMakeLists-txt-422)

```c
   419 │ 	)
   420 │ 
   421 │ 	# create nsh_romfsimg.c
▶  422 │ 	add_custom_command(OUTPUT nsh_romfsimg.c
   423 │ 		COMMAND ${CMAKE_COMMAND} -E remove -f nsh_romfsimg.c
   424 │ 		COMMAND ${CMAKE_BINARY_DIR}/gencromfs ${romfs_gen_root_dir} nsh_romfsimg.c
   425 │ 		DEPENDS
```
> **说明**：改 boards/rm2027/fmu-h743/init/rc.board_sensors 后没生效 | 没重新编译 ⇒ ROMFS 未重建 | ROMFS/CMakeLists.txt:422 |
^src-ROMFS-CMakeLists-txt-422

### `ROMFS/px4fmu_common/CMakeLists.txt`
<a id="src-ROMFS-px4fmu-common-CMakeLists-txt-34"></a>
**↓ 文档在讲这里：**[`ROMFS/px4fmu_common/CMakeLists.txt:34`](romfs.md#^src-ROMFS-px4fmu-common-CMakeLists-txt-34)

```c
    31 │ #
    32 │ ############################################################################
    33 │ 
▶   34 │ add_subdirectory(init.d)
    35 │ # TODO: make this configurable from the board config, or better combine
    36 │ if("${PX4_BOARD}" MATCHES "sitl")
    37 │ 	add_subdirectory(init.d-posix)
```
> **说明**：1 | ROMFS/CMakeLists.txt:74 add_subdirectory(${romfs_src_dir}) | 进 ROMFS/px4fmu_common/（再 ROMFS/px4fmu_common/CMakeLists.txt:34 进 init.d/） |
^src-ROMFS-px4fmu-common-CMakeLists-txt-34

### `boards/rm2027/fmu-h743/bootloader.px4board`
<a id="src-boards-rm2027-fmu-h743-bootloader-px4board-3"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/bootloader.px4board:3`](romfs.md#^src-boards-rm2027-fmu-h743-bootloader-px4board-3)

```c
     1 │ CONFIG_BOARD_TOOLCHAIN="arm-none-eabi"
     2 │ CONFIG_BOARD_ARCHITECTURE="cortex-m7"
▶    3 │ CONFIG_BOARD_ROMFSROOT=""
     4 │ 
```
> **说明**：bootloader.px4board:3 | CONFIG_BOARD_ROMFSROOT="" | default.px4board 里为 px4fmu_common |
> **说明**：rc.serial / rc.autostart / rc.filepaths 在源码树里找不到 | 它们是构建期生成的 | ROMFS/CMakeLists.txt:142、:153-161 | ┃ bootloader 里 /etc 不存在 | CONFIG_BOARD_ROMFSROOT="" | bootloader.px4board:3 |
^src-boards-rm2027-fmu-h743-bootloader-px4board-3

### `build/rm2027_fmu-h743_default/ROMFS/nsh_romfsimg.c`
<a id="src-build-rm2027-fmu-h743-default-ROMFS-nsh-romfsimg-c-33"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/ROMFS/nsh_romfsimg.c:33`](romfs.md#^src-build-rm2027-fmu-h743-default-ROMFS-nsh-romfsimg-c-33)

```c
    30 │ 
    31 │ /* CROMFS image */
    32 │ 
▶   33 │ const uint8_t aligned_data(4) g_cromfs_image[] =
    34 │ {
    35 │   /* Offset      0:  Volume header */
    36 │ 
```
> **说明**：串口打出的 rcS 行号与源码树对不上 | px_romfs_pruner.py 去注释 | ROMFS/CMakeLists.txt:401 + rcS:14 | ┃ 固件体积比预期大很多 | ROMFS 数组直接进 .rodata | nsh_romfsimg.c:33 |
^src-build-rm2027-fmu-h743-default-ROMFS-nsh-romfsimg-c-33

### `platforms/nuttx/CMakeLists.txt`
<a id="src-platforms-nuttx-CMakeLists-txt-191"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:191`](romfs.md#^src-platforms-nuttx-CMakeLists-txt-191)

```c
   188 │ 		gcc
   189 │ 		)
   190 │ 
▶  191 │ 	if (config_romfs_root)
   192 │ 		add_subdirectory(${PX4_SOURCE_DIR}/ROMFS ${PX4_BINARY_DIR}/ROMFS)
   193 │ 		target_link_libraries(px4_kernel PRIVATE romfs)
   194 │ 	endif()
```
> **说明**：⇒ CMake 变量 | config_romfs_root 为空 | 非空 | ┃ ⇒ platforms/nuttx/CMakeLists.txt:191 的 if (config_romfs_root) | 假 ⇒ 不 add_subdirectory(ROMFS)、不链 romfs | 真 ⇒ 链 romfs |
^src-platforms-nuttx-CMakeLists-txt-191

<a id="src-platforms-nuttx-CMakeLists-txt-394"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:394`](romfs.md#^src-platforms-nuttx-CMakeLists-txt-394)

```c
   391 │ 
   392 │ 	target_link_libraries(px4 PRIVATE ${module_libraries})
   393 │ 
▶  394 │ 	if(config_romfs_root)
   395 │ 		add_subdirectory(${PX4_SOURCE_DIR}/ROMFS ${PX4_BINARY_DIR}/ROMFS)
   396 │ 		target_link_libraries(px4 PRIVATE romfs)
   397 │ 	endif()
```
> **说明**：7 | ROMFS/CMakeLists.txt:412（cromfs 分支） | 编 host 工具 gencromfs（:415）→ gencromfs <build>/etc nsh_romfsimg.c（:424）→ add_library(romfs STATIC nsh_romfsimg.c)（:431） | ┃ 8 | platforms/nuttx/CMakeLists.txt:394 | target_link_libraries(px4 PRIVATE romfs) ⇒ 数组被链进固件 |
^src-platforms-nuttx-CMakeLists-txt-394

### `platforms/nuttx/NuttX/nuttx/fs/cromfs/fs_cromfs.c`
<a id="src-platforms-nuttx-NuttX-nuttx-fs-cromfs-fs-cromfs-c-231"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/fs/cromfs/fs_cromfs.c:231`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-fs-cromfs-fs-cromfs-c-231)

```c
   228 │  * This is the address of the single CROMFS file system image:
   229 │  */
   230 │ 
▶  231 │ extern const struct cromfs_volume_s g_cromfs_image;
   232 │ 
   233 │ /****************************************************************************
   234 │  * Private Functions
```
> **说明**：cromfs 是"文件系统类型"，不是块设备： ┃ nuttx/fs/cromfs/fs_cromfs.c:231 直接 extern const struct cromfs_volume_s g_cromfs_image;
^src-platforms-nuttx-NuttX-nuttx-fs-cromfs-fs-cromfs-c-231

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-128"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:128`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-128)

```c
   125 │ 
   126 │ #ifdef CONFIG_ETC_ROMFS
   127 │ #  define NSECTORS(b)        (((b)+CONFIG_ETC_ROMFSSECTSIZE-1)/CONFIG_ETC_ROMFSSECTSIZE)
▶  128 │ #  define MKMOUNT_DEVNAME(m) "/dev/ram" STRINGIFY(m)
   129 │ #  define MOUNT_DEVNAME      MKMOUNT_DEVNAME(CONFIG_ETC_ROMFSDEVNO)
   130 │ 
   131 │ extern const unsigned char romfs_img[];
```
> **说明**：:1442-1446 在 bind() 里 DEBUGASSERT(g_cromfs_image.cv_magic == CROMFS_MAGIC) 后 *handle = &g_cromfs_image ┃ ⇒ nx_bringup.c:128 里的 MOUNT_DEVNAME = "/dev/ram0" 只是个形式参数，没有真的块设备。
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-128

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-131"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:131`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-131)

```c
   128 │ #  define MKMOUNT_DEVNAME(m) "/dev/ram" STRINGIFY(m)
   129 │ #  define MOUNT_DEVNAME      MKMOUNT_DEVNAME(CONFIG_ETC_ROMFSDEVNO)
   130 │ 
▶  131 │ extern const unsigned char romfs_img[];
   132 │ extern const unsigned int romfs_img_len;
   133 │ #endif
   134 │ 
```
> **说明**：⇒ CONFIG_ETC_CROMFS=y 时用的是 g_cromfs_image，而 nx_bringup.c:131 里声明的
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-131

### `platforms/nuttx/NuttX/nuttx/tools/gencromfs.c`
<a id="src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-170"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/tools/gencromfs.c:170`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-170)

```c
   167 │ {
   168 │   uint8_t lzf_magic[2];   /* [0]='Z', [1]='V' */
   169 │   uint8_t lzf_type;       /* LZF_TYPE0_HDR */
▶  170 │   uint8_t lzf_len[2];     /* Data length (big-endian) */
   171 │ };
   172 │ 
   173 │ struct lzf_type1_header_s /* Compressed data header */
```
> **说明**：只说"它改变了最终镜像里的行结构"，依据是 ROMFS/CMakeLists.txt:401 的调用 + rcS:14 的注释。 ┃ gencromfs 的压缩算法（LZF）与解压时机未展开（gencromfs.c:170 有 lzf_len 字段，未深读）。
^src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-170

<a id="src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-1315"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/tools/gencromfs.c:1315`](romfs.md#^src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-1315)

```c
  1312 │   /* Now append the volume header to output file */
  1313 │ 
  1314 │   fprintf(g_outstream, "/* CROMFS image */\n\n");
▶ 1315 │   fprintf(g_outstream, "const uint8_t aligned_data(4) g_cromfs_image[] =\n");
  1316 │   fprintf(g_outstream, "{\n");
  1317 │   fprintf(g_outstream, "  /* Offset %6lu:  Volume header */\n\n", 0ul);
  1318 │ 
```
> **说明**：gencromfs.c:1315 就是这一行的出处。
^src-platforms-nuttx-NuttX-nuttx-tools-gencromfs-c-1315
