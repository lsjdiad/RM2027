# 参数系统的代码孪生

> 本篇是 `[../../03_moc/04-params-map](../../03_moc/04-params-map.md)` 的 02 层展开 —— 那边讲"一个参数的一生"，
> 这边讲**支撑它的那几个源文件**各自管什么、什么时候被调用。
>
> 视角仍是运行时。

---

## 1. `src/lib/parameters/` 的关键角色

| 文件 | 管什么 |
|---|---|
| **`param.cpp`** | `param` 这个 **nsh 命令**（`param set/get/show/save/load/select`）的实现；**它的 `--help` 文本就是"参数怎么存"的官方说明**（:107-116） |
| `param.h` | 参数 API 声明：`param_find` / `param_get` / `param_set` / `param_handle_register` |
| **`param_transaction.cpp`** | 批量读写的事务层（避免逐个写 flash） |
| **flash backend**（`flashfs`） | 片内 flash 的存储后端；**本板启用的就是它**（[`board_config.h:60`](param-system.md#^src-boards-rm2027-fmu-h743-src-board-config-h-60) 的 `FLASH_BASED_PARAMS`） |

**★ 关键：[`param.cpp:107`](param-system.md#^src-src-systemcmds-param-param-cpp-107) 的原文就是最权威的文档：**
> *"Parameters are **automatically saved when changed**, eg. with `param set`. They are typically stored to
> FRAM or to the SD card. `param select` can be used to change the storage location for subsequent saves."*
> *"If the **FLASH-based backend** is enabled (which is done at compile time), `param select` has no effect
> and the default is always the FLASH backend."*

**⇒ 所以"要不要 `param save`"这个问题在 PX4 里不成立 —— 改了就存。**

---

## 2. 生成层：`generated_params/module_params.c`

| 项 | 事实（实测） |
|---|---|
| 位置 | `build/rm2027_fmu-h743_default/generated_params/module_params.c` |
| 规模 | **1464 个 `PARAM_DEFINE`** |
| 内容 | 参数名 + 默认值 + **`@description` / `@value` 注释**（这些注释就是 QGC 里显示的说明文字） |
| 谁生成 | 构建期由参数生成器扫描源码注释 / 模块 yaml 得到 |
| 典型条目 | `PARAM_DEFINE_INT32(PWM_MAIN_FUNC1, 0);` / `PARAM_DEFINE_INT32(PWM_MAIN_TIM0, 400);` |

**★ 这个文件是"参数默认值"的**唯一**落点 —— 固件里的默认值就是它。**

---

## 3. 三个参数来源的代码位置

| 来源 | 代码位置 | 产物 |
|---|---|---|
| **① `@param` 注释** | 各模块 `.c/.cpp` 里的 `/** ... PARAM_DEFINE_XXX(...) */` | 同一份 `module_params.c` |
| **② 板级 `CONFIG_*`** | `boards/rm2027/fmu-h743/default.px4board` → Kconfig → CMake | 决定**哪些模块被编**（如 `CONFIG_DRIVERS_DSHOT=y`）⇒ 间接决定哪些参数**存在** |
| **③ 模块 yaml（动态）** | `src/drivers/pwm_out/module.yaml` 等 | **`PWM_MAIN_FUNC1..N` 这种按通道数生成的参数** |

**⇒ ① 和 ③ 都落到同一份 `module_params.c`，分界在于"是写死的还是按数量生成的"。**

---

## 4. 运行时：参数在内存里怎么落地

```
① 模块启动 → param_find("XXX") 拿到 handle（首次会自动注册）
② 实际取值：param_get(handle, &value)
      ↓
   内部：如果 flash 里有该参数的记录 ⇒ 用 flash 的值
         否则 ⇒ 用 module_params.c 里的编译期默认值
③ 修改：param_set(handle, &value) ⇒ 【立即写 flash】（FLASH 后端）
```

**⇒ 所以"参数"在运行时是"内存里的一份当前值 + 一块 flash 的持久副本"，两者靠 `param_set/get` 同步。**

---

## 5. ★ 本板的特殊之处：参数区就是那一个扇区

**🔗 完整前因后果（含 [`init.c:186`](param-system.md#^src-boards-rm2027-fmu-h743-src-init-c-186) 的设计说明原文）见 `[../../03_moc/04-params-map](../../03_moc/04-params-map.md)` §4。**

**代码位置速查：**
```
boards/rm2027/fmu-h743/src/board_config.h:60    #define FLASH_BASED_PARAMS
boards/rm2027/fmu-h743/src/init.c:201           {15, 128 * 1024, 0x081E0000},
boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:113
                                                FLASH (rx) : ORIGIN = 0x08020000, LENGTH = 1792K
```

**⚠️ 三处必须同源：改一处要改其余两处，否则"参数写入会打烂代码"。**

---

## 6. 跳转

- **参数的一生（MOC）** → `[../../03_moc/04-params-map](../../03_moc/04-params-map.md)`
- **构建期参数怎么被生成** → `[../../03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)`
- **参数被哪些模块读走** → `[../../03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md)`
- **25 个板级文件里 `rc.board_defaults` 的执行时机** → `[../board/README](../board/README.md)`（D 组）

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/src/board_config.h`
<a id="src-boards-rm2027-fmu-h743-src-board-config-h-60"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/board_config.h:60`](param-system.md#^src-boards-rm2027-fmu-h743-src-board-config-h-60)

```c
    57 │ //   不开这个 ⇒ 每次上电参数全丢、标定白做。故开启片内 flash 存参数，
    58 │ //   占用最后一个 128K 扇区 0x081E0000（配套 script.ld 的 FLASH LENGTH 1792K）。
    59 │ //   详见 src/init.c 里 params_sector_map 的注释。
▶   60 │ #define FLASH_BASED_PARAMS
    61 │ 
    62 │ 
    63 │ /* ============================================================================
```
> **说明**：param_transaction.cpp | 批量读写的事务层（避免逐个写 flash） | ┃ flash backend（flashfs） | 片内 flash 的存储后端；本板启用的就是它（board_config.h:60 的 FLASH_BASED_PARAMS） |
^src-boards-rm2027-fmu-h743-src-board-config-h-60

### `boards/rm2027/fmu-h743/src/init.c`
<a id="src-boards-rm2027-fmu-h743-src-init-c-186"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:186`](param-system.md#^src-boards-rm2027-fmu-h743-src-init-c-186)

```c
   183 │ #endif
   184 │ 
   185 │ 
▶  186 │ #if defined(FLASH_BASED_PARAMS)
   187 │ 	/* ★ rm2027/fmu-h743：本板【既没有 SD 卡也没有 USB】，参数无处可存 ——
   188 │ 	 *   不开这个就等于"每次上电参数全丢，标定白做"。所以必须用片内 flash 存。
   189 │ 	 *
```
> **说明**：🔗 完整前因后果（含 init.c:186 的设计说明原文）见 ../../03_moc/04-params-map §4。
^src-boards-rm2027-fmu-h743-src-init-c-186

### `src/systemcmds/param/param.cpp`
<a id="src-src-systemcmds-param-param-cpp-107"></a>
**↓ 文档在讲这里：**[`src/systemcmds/param/param.cpp:107`](param-system.md#^src-src-systemcmds-param-param-cpp-107)

```c
   104 │ ### Description
   105 │ Command to access and manipulate parameters via shell or script.
   106 │ 
▶  107 │ This is used for example in the startup script to set airframe-specific parameters.
   108 │ 
   109 │ Parameters are automatically saved when changed, eg. with `param set`. They are typically stored to FRAM
   110 │ or to the SD card. `param select` can be used to change the storage location for subsequent saves (this will
```
> **说明**：★ 关键：param.cpp:107 的原文就是最权威的文档：
^src-src-systemcmds-param-param-cpp-107
