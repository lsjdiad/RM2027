# 参数：一个参数的一生

> **本篇回答"参数调整的梳理"。视角仍然是运行时：**
> **一个参数从哪来、编进哪里、开机时被谁读走、你在 QGC 里点一下之后发生了什么。**
>
> 所有行号可直接跳转，不用自己翻。

---

## 0. 一句话答案

**参数不是"配置文件"，而是"编进固件的默认值 + 一块 flash 里的覆盖表"。**
运行时模块调 `param_get()` 时取到的是**两者合并后的结果**。

```
源码里的 PARAM_DEFINE  ──编译──→  固件里的默认值表
                                      │
                       开机加载 ──────┤
                                      │
flash 参数区（0x081E0000）──覆盖──→ 内存里的当前值 ──param_get()──→ 模块
```

---

## 1. 一个参数的一生（以 `PWM_MAIN_FUNC1` 为例，逐跳）

**这是本板真实存在的一个参数，而且是"最不典型"的一个** —— 它**不是** `PARAM_DEFINE` 写死的，
而是**运行时按输出通道数动态生成的**。用它当例子，能把机制讲透。

```
① 谁"定义"它
   src/drivers/pwm_out/module.yaml  （描述这个模块有哪些参数、什么前缀）
      ↓ 生成器读 yaml
② 生成
   build/rm2027_fmu-h743_default/generated_params/module_params.c
      ⇒ PARAM_DEFINE_INT32(PWM_MAIN_FUNC1, 0);
      ⇒ PARAM_DEFINE_INT32(PWM_MAIN_TIM0, 400);
   ★ 注意默认值：FUNC1 = 0（Disabled）、TIM0 = 400（PWM 400Hz，不是 DShot）
      ↓ 编进固件
③ 编进二进制的"默认值表"
      ↓ 开机
④ 加载：模块启动时注册参数，然后从【flash 参数区】读覆盖值
      参数区 = 0x081E0000 那个 128K 扇区（见 §4）
      ↓
⑤ 被谁读走
   src/drivers/dshot/DShot.cpp:1086   读 PWM_MAIN_TIM0  ⇒ 决定输出协议
   src/drivers/dshot/DShot.cpp         读 PWM_MAIN_FUNCx ⇒ 决定通道绑哪个功能
   src/drivers/pwm_out/PWMOut.cpp      也读同一个 TIM0   ⇒ 决定 PWM 频率
      ↓
⑥ 你改它（QGC / param set）⇒ 立即写 flash（自动保存）⇒ 但【大部分参数要重启才生效】
```

**★ 关键：同一个参数名 `PWM_MAIN_TIM0` 被**两条驱动路径**读走 ⇒ 这就是"改了却还是 PWM"的成因**
（详见 §5）。

---

## 2. 参数的三种来源

| # | 来源 | 谁生成 | 产物落在哪 | 例子 |
|---|---|---|---|---|
| **1** | **源码注释 `@param`** | 构建期扫描 | `build/.../generated_params/*.c` | `EKF2_GPS_CTRL`、`IMU_GYRO_CUTOFF` |
| **2** | **板级 `CONFIG_*`** | Kconfig → 生成器 | 同上（模块参数）+ 编译宏 | `CONFIG_DRIVERS_DSHOT=y` ⇒ 生成 `DSHOT_*` |
| **3** | **模块 yaml（动态）** | 模块自己声明 | 同上 | **`PWM_MAIN_FUNC1..N`**（按通道数生成） |

**⇒ 本板 `generated_params/module_params.c` 里一共有 `1464` 个 `PARAM_DEFINE`。**

---

## 3. 落盘：改了就存吗？（★ 这条最容易搞错）

### 3.1 官方语义（[`src/systemcmds/param/param.cpp:107`](../02_code_twin/params/param-system.md#^src-src-systemcmds-param-param-cpp-107) 原文）

> *"Parameters are **automatically saved when changed**, eg. with `param set`."*
> *"If the **FLASH-based backend** is enabled (which is done at compile time), `param select` has no effect
> and the default is always the FLASH backend."*

### 3.2 本板用的就是 FLASH 后端

```
boards/rm2027/fmu-h743/src/board_config.h:60
    #define FLASH_BASED_PARAMS
```

**⇒ 所以：**
```
✅ 改参数【自动落盘】，不需要手动 param save
✅ param select 在本板无意义（永远是 FLASH 后端）
✅ 但仍可用 param save/load <file> 做导入导出
```

### 3.3 那"坑"在哪？—— 在**持久化到底生效没**

**真正要验证的是"断电后还在不在"，而不是"要不要 save"。**
```
唯一可靠动作：
    ① 配好参数
    ② 【断电】
    ③ 上电
    ④ param show PWM_MAIN_FUNC1 PWM_MAIN_TIM0 SYS_AUTOSTART
    ⇒ 还在 ⇒ 持久化生效；丢了 ⇒ 去查 §4 的三处同源
```

**⚠️ 而这条**在本板从未端到端验收过**（这是本项目的一条已知欠账）。**

---

## 4. ★★ flash 参数区：三处必须同源（本板的设计说明原文）

**[`boards/rm2027/fmu-h743/src/init.c:186`](../02_code_twin/params/param-system.md#^src-boards-rm2027-fmu-h743-src-init-c-186) 的注释把这件事讲得很清楚，值得逐字读：**

| 要点 | 内容 |
|---|---|
| **为什么必须开 FLASH 后端** | **本板既没有 SD 卡也没有 USB** ⇒ 参数无处可存 ⇒ 不开等于"每次上电参数全丢，标定白做" |
| **扇区选择** | H743 是 2 MB **双 bank**、每 bank 8 个 **128 K** 扇区 ⇒ **bank2 最后一个扇区 = 扇区 15 = `0x081E0000`**，正好在 app 区之外 |
| **上游先例** | 同 MCU 的 4 块板（`aedrox/aedroxh7`、`corvon/743v1`、`corvon/743v2`、`cbunmanned/h753-som`）**全都只用一个扇区** |
| **单扇区合法吗** | 合法 —— `flashfs` 的 `get_next_sector_descriptor()` 在只有一项时会回到自己（**代价：没有扇区级磨损均衡**） |
| **★ 配套要求** | **`script.ld` 的 `FLASH LENGTH` 必须从 1920K 缩到 1792K**，把 `0x081E0000` 让出来，**否则链接器可能把代码放进去、参数写入就会打烂代码** |

**实际代码：**
```
init.c:201      {15, 128 * 1024, 0x081E0000},
script.ld:113   FLASH (rx) : ORIGIN = 0x08020000, LENGTH = 1792K  /* 最后 1 个 128K 扇区让给参数存储 */
```

**⇒ ⇒ 所以"三处同源"= ① `board_config.h` 的 `FLASH_BASED_PARAMS`、② `script.ld` 的 `FLASH LENGTH`、
③ `init.c` 的扇区描述表 —— **改一处必须改其余两处**。**

**⚠️ 另有一处数值不同源（ct-cmake 发现，标注为推理）：**
```
script.ld:113           FLASH LENGTH = 1792K
.px4 镜像头 image_maxsize = 1966080 (1920K)
⇒ 差 128K，正好是让给参数区的那个扇区
```

---

## 5. ★ 用本板已踩的坑演示"参数怎么影响行为"

**现象**：配了 `PWM_MAIN_FUNC1..4`，输出却一动不动。
**机制**（每一跳都有实测证据）：

```
PWM_MAIN_TIM0 默认 = 400
    ↓ DShot.cpp:1086   snprintf(param_name, "%s_TIM%u", ...) ⇒ 读 PWM_MAIN_TIM0
    ↓ DShot.cpp:1096-1110 的 switch【只认 -8/-7/-6/-5/-4/-3】
        DShot.h:59-64   DSHOT150=-5 / DSHOT300=-4 / DSHOT600=-3
                        BDSHOT150=-8 / BDSHOT300=-7 / BDSHOT600=-6
    ↓ 400 不在表里 ⇒ 走 default ⇒ 通道数 = 0
    ↓ DShot.cpp:1126-1128   if (dshot_timer_channels == 0) { PX4_INFO("No channels configured"); return false; }
⇒ 【DShot 驱动直接退出，一个脉冲都不发】

同时同一个参数字符串被另一条路径读走：
    PWMOut.cpp 读 PWM_MAIN_TIM0 ⇒ _timer_rates[0] = 400 ⇒ 【输出变成 PWM 400Hz】
```

**⇒ **这解释了为什么"只配 FUNC 不配 TIM0"看起来和"根本没配"一模一样** —— 都是没输出。**

**另一条：`DSHOT_BIDIR_EDT` 默认 0** ⇒ 双向 DShot 遥测默认关 ⇒ 与我们"用单向"的决定天然一致。

---

## 6. 本板参数的分类（**只列组与代表项**，共 1464 个）

| 组 | 代表参数 | 谁读它 |
|---|---|---|
| **传感器** | `CAL_ACC0_PRIO` / `CAL_GYRO0_PRIO` / `IMU_GYRO_CUTOFF` / `IMU_INTEG_RATE` | 各驱动 + `sensors` |
| **EKF（估计器）** | `EKF2_GPS_CTRL` / `EKF2_MAG_TYPE` / `EKF2_HGT_REF` | `ekf2` |
| **控制** | `MC_ROLL_P` / `MC_PITCH_P` / `MPC_XY_VEL_MAX` / `MC_*_RATE_*` | `mc_att_control` / `mc_rate_control` / `mc_pos_control` |
| **输出/混控** | **`PWM_MAIN_FUNC1..N`** / **`PWM_MAIN_TIM0`** / `PWM_MAIN_MIN1..4` / `PWM_MAIN_DIS1..4` | `DShot` / `PWMOut` / `MixingOutput` |
| **DShot 专属** | `DSHOT_ESC_TYPE` / `DSHOT_MIN` / `DSHOT_MOT_POL1..12` / `DSHOT_BIDIR_EDT` / `DSHOT_3D_ENABLE` | `DShot.cpp` |
| **机型/几何** | `SYS_AUTOSTART`（4001 = Generic Quadcopter）/ `CA_ROTOR*_PX/PY/KM` | `rc.vehicle_setup` → `control_allocator` |
| **MAVLink/通信** | `MAV_0_MODE` / `MAV_0_RATE` / `MAV_0_FORWARD` | `mavlink` |
| **系统** | `CBRK_SUPPLY_CHK`（894281 关电源检查）/ `CBRK_USB_CHK`（197848）/ `SYS_HITL` | `commander` / 各检查 |

**🔗 完整分组清单**：跳去 `build/rm2027_fmu-h743_default/generated_params/module_params.c` 按 `PARAM_DEFINE` 搜。

---

## 7. 改参数的三个入口（★ 生效时机不同）

| 入口 | 时机 | 优先级 | 说明 |
|---|---|---|---|
| **① 板级默认值文件** | **开机 rcS 阶段** | 最低（但**每次开机都重设**） | `boards/rm2027/fmu-h743/init/rc.board_defaults`（rcS:278 处被 source）—— 用 `param set` 写 |
| **② QGC** | 在线，改完立即写 flash | 中 | 走 MAVLink 参数协议 |
| **③ `param set`（nsh 手工）** | 在线 | 中 | 改完**自动落盘**（§3） |

**★ 关键认知：`rc.board_defaults` 是"每次开机都设一遍"，而 QGC 改的是"flash 里的当前值"。**
```
⇒ 如果某个参数在 rc.board_defaults 里被写死 ⇒ 【你在 QGC 里改它，下次开机又被打回去】
⇒ 这解释了"QGC 里改了却总是恢复"的现象（若真的出现）
```

---


---

## 9. ★ 补充（ct-boot 发现 + lead 复核）：走 bootloader 刷固件**会擦掉参数区**

**这条在本项目里值得单独记，因为它直接影响"标定会不会白做"。**

**证据链（全部可复核）：**
```c
// ① 擦除循环覆盖到扇区 15（= 参数区 0x081E0000）
bl.c:777-780
    for (int i = 0; flash_func_sector_size(i) != 0; i++) {
        flash_func_erase_sector(i, full_erase);
    }

// ② 终止条件：i=16 时返回 0
main.c:470-472
    if (sector <= BOARD_FLASH_SECTORS) return FLASH_SECTOR_SIZE;   // BOARD_FLASH_SECTORS = 15
    return 0;

// ③ 擦除闸门：只要扇区"有内容"就擦
main.c:477-483
    if (force || (up_progmem_ispageerased(sector) != 0)) {
        up_progmem_eraseblock(sector);
    }
// up_progmem_ispageerased() 返回的是【已写字节数】(stm32h743xx_flash.c:717-718)，
// 不是布尔 ⇒ 有任何一个非 0xFF 字节就非 0 ⇒ 擦

// ④ 本板没有为参数区保留任何空间
hw_config.h:121   #define APP_RESERVATION_SIZE 0
hw_config.h:104   #define BOARD_FLASH_SECTORS (15)
```

**⇒ 结论：**
```
走 bootloader（QGC / px_uploader）刷固件
   ⇒ 擦除循环覆盖扇区 1..15
   ⇒ 【扇区 15 = flash 参数区被擦掉】
   ⇒ 参数回到编译期默认值
```

**⇒ ⇒ 这与"PX4 刷固件不丢参数"的常识**不冲突** —— 因为 **QGC 会先读出参数、刷完再写回**，
不是 bootloader 保住了它们 ✓**

**⚠️ 另一处三方不同源（bootloader 侧 1920K vs app 侧 1792K）：**
```
main.c:86    APP_SIZE_MAX = BOARD_FLASH_SIZE - (BOOTLOADER_RESERVATION_SIZE + APP_RESERVATION_SIZE)
             = 2048K - 128K - 0 = 【1920K】
script.ld:113 FLASH LENGTH = 【1792K】
.px4 头       image_maxsize = 1966080 = 【1920K】 ← 与 bootloader 一致
```
**⇒ 所以：bootloader 认为 app 占**扇区 1..15**，而 app 自己的链接脚本只占**扇区 1..14**
⇒ [`bl.c:902`](../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-902) 的 **CRC 计算范围包含参数区**（`fw_size` = 1920K）。

**⇒ 这在实际行为上不致命**（bootloader 只在**上传时**校验 CRC，不是每次开机校验；上传时参数区刚被擦成全 0xFF ⇒ CRC 自洽），
**但它意味着：一旦参数被改写，用 1920K 范围算出的 CRC 就不再匹配——如果哪天有人改成"每次开机校验"，就会误判镜像损坏。**

**🔗 上板判据（若要在台架上确认）**：见 `[01_extracted/stm32/flash-layout](../01_extracted/stm32/flash-layout.md)` §5 的两条。

## 8. 跳转：接下来读哪一篇

- **参数怎么生成、CMake 变量怎么展开** → `[00-build-walkthrough](00-build-walkthrough.md)`（★ 本篇 §1 的前半段在那展开）
- **参数被哪些模块读走、信息怎么流** → `[02-sensor-flow](02-sensor-flow.md)`
- **module 怎么启停、uORB 是什么** → `[03-module-map](03-module-map.md)`
- **板级 25 个文件里 `rc.board_defaults` 的执行时机** → `[02_code_twin/board/rc-board-defaults](../02_code_twin/board/README.md)`
- **flash 布局与参数区的完整前因后果** → `[01_extracted/stm32/flash-layout](../01_extracted/stm32/flash-layout.md)`
- **参数机制的源码级细节** → `[02_code_twin/params/param-system](../02_code_twin/params/param-system.md)`

---

## 源码在哪（本篇只讲流程；代码与逐行解释已归位到 02 层）

> ★ **本篇每一条 `文件:行` 都能点** —— 它跳到 `02_code_twin/` 里对应的篇，代码旁边就是解释。
> 三层各司其职：**01 讲语法/机制通则 · 02 讲某个文件的行号在干什么 · 03 只讲流程**。

| 代码在 | 02 层的篇 |
|---|---|
| `02_code_twin/bootloader/00-overview.md` | [`02_code_twin/bootloader/00-overview.md`](../02_code_twin/bootloader/00-overview.md) |
| `02_code_twin/params/param-system.md` | [`02_code_twin/params/param-system.md`](../02_code_twin/params/param-system.md) |
