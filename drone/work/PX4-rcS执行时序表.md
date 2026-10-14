# rcS 执行时序表（本板 rm2027/fmu-h743）

> **用途**：你在从头复刻 `boards/rm2027/fmu-h743/`，其中 `init/rc.board_sensors` 等钩子要自己写。
> 本表只回答三件事：**它在什么时机被调用 / 谁调用它 / 看到什么日志才算成功**。
> **只讲时机与判据，不贴脚本内容。** 全部行号基于 `ROMFS/px4fmu_common/init.d/rcS`（共 797 行）。

---

## 0. 先说清楚：rcS 是谁跑起来的

| 环节 | 依据 |
|---|---|
| NuttX 内核起来后**直接进 shell** | `boards/rm2027/fmu-h743/nuttx-config/nsh/defconfig:116` → `CONFIG_INIT_ENTRYPOINT="nsh_main"` |
| nsh 执行的启动脚本名 = **`init.d/rcS`** | `build/rm2027_fmu-h743_default/NuttX/nuttx/.config:2095` → `CONFIG_NSH_INITSCRIPT="init.d/rcS"` |
| 这个键**不写也有值**（编译期兜底默认） | `platforms/nuttx/NuttX/apps/nshlib/nsh.h:299-300`（`#ifndef CONFIG_NSH_INITSCRIPT` → `#define "init.d/rcS"`） |
| 路径 = **ROMFS 挂载点** ＋ 该键 ⇒ **rcS 是从 ROMFS 里跑的** | `nsh.h:307` → `NSH_INITPATH = CONFIG_ETC_ROMFSMOUNTPT "/" CONFIG_NSH_INITSCRIPT` |
| 构建期：用这个键决定把哪个脚本打进 ROMFS 映像 | `platforms/nuttx/NuttX/nuttx/tools/mkromfsimg.sh:90` |
| **rcS 之前还有一个 sysinit** | `nsh.h:296-297`（`CONFIG_NSH_SYSINITSCRIPT`）＋ `.config:2094`；`ROMFS/px4fmu_common/init.d/rc.sysinit` 在本仓里是 **44 字节空壳**（只有 shebang 与注释，实际不做事） |

⇒ 所以真机开机链的**脚本段**是：`nsh → rc.sysinit（空壳）→ rcS`。

---

## 1. 六个板级/平台级钩子，分别插在哪

| 钩子 | rcS 行号 | 时机 | 日志判据 | 来源机制 |
|---|---|---|---|---|
| `rc.board_early` | `:64` | **最早**（存储挂载**之前**） | ⚠️ **无任何 echo** —— 六个钩子里唯一没有日志的 | 板级 `init/`；白名单 `ROMFS/CMakeLists.txt:195-201` |
| `rc.board_arch_defaults` | `:270` | 参数加载后、机型加载前 | `Board architecture defaults: ...`（`:270`） | **平台层**，不是板级：`ROMFS/CMakeLists.txt:170-171`（`platforms/<platform>/init/<chip>/`） |
| `rc.board_defaults` | `:278` | 机型加载**之前** | `Board defaults: ...`（`:281`） | 板级 `init/` |
| **`rc.board_sensors`** | `:420` | **传感器段，通用 `rc.sensors` 之前** | **`Board sensors: ...`（`:423`）** | 板级 `init/` |
| `rc.board_mavlink` | `:591` | 通信段 | `Board mavlink: ...`（`:594`） | 板级 `init/` |
| `rc.board_extras` | `:693` | 收尾段 | `Board extras: ...`（`:696`） | 板级 `init/` |

**本板实际提供 3 个**（构建产物 `build/rm2027_fmu-h743_default/etc/init.d/` 核对）：
`rc.board_defaults`、`rc.board_sensors`、`rc.board_extras`。
⇒ `rc.board_early` / `rc.board_mavlink` 本板**没有** ⇒ 运行时 `if [ -f ]` 判空后**直接跳过，不报错**（`:421`、`:592`）。

---

## 2. 阶段表（`:1` → `:797`）

| 行号段 | 阶段 | 干了什么（归纳） | 日志判据 |
|---|---|---|---|
| `:1-18` | 脚本头 | 调试开关（`set -x` 被注释）；注释行在打进 ROMFS 时会被剥掉（`:14`） | — |
| `:19-30` | 环境初始化 | `set R /`、`. rc.filepaths`、设 `FCONFIG/FEXTRAS/FRC`、`LOGGER_ARGS` | — |
| `:58` | **打印版本** | `ver all` | 串口打出硬件/固件版本 |
| `:41-56` | 特性门 + 参数版本 | 细粒度特性开关；`PARAM_DEFAULTS_VER` 机制 | — |
| `:61-70` | **钩子① `rc.board_early`** | 存在则 source（可为 rcS 预设环境变量） | ⚠️ **无日志** |
| `:72-171` | **存储挂载/检查** | 挂 SD、按需格式化、CAN 固件暂存目录、`ext_autostart` 更新 | `INFO [init] format /dev/mmcsd0 requested`(`:85`)、`formatting`(`:97`)、`card formatted`(`:102`)、`ERROR ... card mount failed`(`:109`) |
| `:171-179` | SD 上的 init 脚本 | 找到就**禁用 autostart** | — |
| `:179-255` | **参数加载（核心）** | `param load-or-init`（空白存储首次播种）、失败时导入备份、修复校准数据尺寸 | `ERROR [init] param load-or-init failed`(`:206`)、`[init] importing from parameter backup`(`:222`)、`New /fs/mtd_caldata size is:`(`:191`) |
| `:255-265` | 参数重置 | `SYS_AUTOCONFIG==1` ⇒ `param reset_all`（保留机型/校准/飞行时长等） | — |
| `:265-276` | **钩子② `rc.board_arch_defaults`** | 平台/芯片级默认参数 | `Board architecture defaults: ...`(`:270`) |
| `:276-287` | **钩子③ `rc.board_defaults`** | 板级默认参数 | `Board defaults: ...`(`:281`) |
| `:287-297` | `rc.additional_init` | 附加初始化脚本（第 7 个钩子，非本板） | `Board additional init: ...`(`:292`) |
| `:297-319` | **机型加载** | 按 `SYS_AUTOSTART` 跑机型脚本（`:299` `. rc.autostart`）⇒ 设 `VEHICLE_TYPE`、写 `CA_ROTOR_*` 等 | 失败：`ERROR [init] No airframe file found for SYS_AUTOSTART value`(`:314`) |
| `:319-340` | 校准默认 + 参数版本核对 | 版本不匹配则复位参数 | `Switched to different parameter version. Resetting parameters.`(`:332`) |
| `:340-346` | `tone_alarm` | 蜂鸣器（**参数加载之后**才起，受 `CBRK_BUZZER`） | — |
| `:346-361` | `dataman` | 航点存储 | — |
| `:361-379` | 事件/故障/负载 | socket 事件发送、hardfault streamer、资源负载监控 | — |
| `:379-387` | 状态指示 | system state indicator | — |
| `:387-397` | 用户配置覆盖 | SD 上 `config.txt` 覆盖参数 | `Custom: ${FCONFIG}`(`:391`) |
| **`:397-443`** | ★ **传感器段** | 见 §3-A | `Board sensors: ...`(`:423`) |
| **`:444-462`** | ★ **估计器段** | 见 §3-B | 无 echo（用 `ekf2 status` 事后查） |
| `:462-497` | `px4io` | 探测 I/O 板并按需升级其固件 | `PX4IO start failed`(`:491`) |
| `:497-506` | heater | 温控 IMU 加热（**必须在 px4io 之后**） | — |
| `:506-512` | RC 输入更新 | 原始 RC → `manual_control`（**commander 之前**） | — |
| `:512-539` | 相机/PPS/RPM | 触发、捕获、PPS（**在 pwm_out 之前**，因为要占 pin） | — |
| **`:539-565`** | ★ **Commander ＋ 输出驱动** | `commander start`；随后 `dshot start` / `pwm_out start`（`PASSTHRU_EN>0` 时反过来留空 ESC 线） | — |
| `:565-578` | UAVCAN / Cyphal | 可选总线 | — |
| **`:578-589`** | ★ **控制段** | 见 §3-C | `No autostart ID found`（`rc.vehicle_setup:105`） |
| `:582-589` | 磁罗盘在线标定 | `MBE_ENABLE==1` ⇒ `mag_bias_estimator start` | — |
| `:589-600` | **钩子④ `rc.board_mavlink`** | 板级 MAVLink 数据流 | `Board mavlink: ...`(`:594`) |
| `:600-610` | **串口驱动** | `. rc.serial`（**自动生成**：`Tools/serial/generate_config.py`）；`ZENOH_ENABLE` ⇒ zenoh | — |
| `:610-613` | RC 输入驱动 | `rc_input start`（**必须在串口配置之后**） | — |
| `:613-625` | **USB / MAVLink** | `cdcacm_autostart`；失败则 `sercon` + `mavlink start -d /dev/ttyACM0` | `Starting MAVLink on /dev/ttyACM0`(`:619`) |
| `:625-634` | 开机音 | 启动音（未禁用且无错时） | — |
| `:634-639` | `navigator` | 导航器（航线/任务） | — |
| `:639-649` | 热标定 | 需要时启动 | — |
| `:649-656` | gimbal | 云台（默认关） | — |
| `:656-672` | 数传 / 光流 | blacksheep telemetry、px4flow 探测 | — |
| `:691-702` | **钩子⑤ `rc.board_extras`** | 板级额外启动项 | `Board extras: ...`(`:696`) |
| `:702-711` | SD 上的 addons | 自定义 addon 脚本 | `Addons script: ${FEXTRAS}`(`:706`) |
| `:711-721` | **logger** | `. rc.logging`（缓存受 `LOGGER_BUF`） | — |
| `:721-734` | VTX | 图传服务 | — |
| `:734-742` | 故障注入 | `SYS_FAILURE_EN` | — |
| `:742-750` | 机型附加参数 | 按 `AUTOSTART` 设环境变量/参数 | — |
| `:750-762` | 只读参数上锁 | 若板级配置了只读参数 | — |
| `:762-767` | autostart 结束 | — | — |
| `:767-795` | 释放变量 | 清空脚本变量以省 RAM | — |
| `:795-797` | **通知启动完成** | `mavlink boot_complete` | QGC 从"等待"变为正常 |

---

## 3. 与**我们这架板**强相关的四段（展开）

### A. 传感器段 `rcS:397-443` ★ 你要写的文件就在这里

| 行号 | 做了什么 |
|---|---|
| `:397` | 注释点明：**必须在 Commander 之前**启动，preflight 检查才有效 |
| `:399` | `if param greater SYS_HITL 0` ⇒ **HITL 模式**：`sensors start -h`，**不启动板级传感器**（`:404` 关 GPS） |
| `:416` | `else` ⇒ **真机分支**（下面全是真机路径） |
| `:420` | `set BOARD_RC_SENSORS .../etc/init.d/rc.board_sensors` |
| `:421-425` | `if [ -f ]` ⇒ `:423` **打日志** ⇒ `:424` **source（执行你的脚本）** |
| `:428` | `. rc.sensors` ⇒ **上游通用传感器**（按参数开关拉各种可选传感器） |
| `:432` | `BAT1_SOURCE==2` ⇒ `esc_battery start` |
| `:437` | `BAT1_SOURCE!=1` ⇒ `battery_status start` |
| `:440` | **`sensors start`** ⇒ ★ **真正的 `sensors` 模块最后才启动** |

> **关键认知**：`:424` 与 `:428` 只是**把驱动模块拉起来**；做传感器聚合、发布 `sensor_combined` 等的 **`sensors` 模块是 `:440` 最后一行才启**。
> **本板对应**：`boards/rm2027/fmu-h743/init/rc.board_sensors`（复刻待办 25 文件之一）
> **成功判据**：开机出现 `Board sensors: /etc/init.d/rc.board_sensors`（`:423`）。
> **没有这一行** ⇒ 你的文件**没进 ROMFS**（查文件名/路径/`ROMFS/CMakeLists.txt:195-201` 白名单），而不是脚本写错。
> **驱动真起来了**用事后命令查：`hxy42688p status`、`listener sensor_accel`。

### B. 估计器段 `rcS:444-462`

| 行号 | 做了什么 |
|---|---|
| `:446` | `EKF2_EN==1` ⇒ **`ekf2 start &`**（注意：**后台**启动） |
| `:451` | `LPE_EN==1` ⇒ `local_position_estimator start` |
| `:456` | `ATT_EN==1` ⇒ `attitude_estimator_q start` |

**本板对应**：无需板级文件；靠参数 `EKF2_EN`（本板缺省 1）等。
**判据**：无 echo ⇒ 用 `ekf2 status`、QGC 的 EKF 状态查。

### C. 控制段 `rcS:578-580` → `rc.vehicle_setup` → `rc.mc_apps`

| 环节 | 依据 |
|---|---|
| `rcS:580` | `. ${R}etc/init.d/rc.vehicle_setup`（按 `VEHICLE_TYPE` 分发） |
| `rc.vehicle_setup:20-24` | `VEHICLE_TYPE = mc` ⇒ `. rc.mc_apps`（多旋翼） |
| `rc.mc_apps:11` | **`control_allocator start`** |
| `rc.mc_apps:16 / :21 / :41 / :42 / :47` | `mc_rate_control` / `mc_att_control` / `flight_mode_manager` / `mc_pos_control` / `land_detector` |

**本板对应**：**不需要板级文件** —— 选对 `SYS_AUTOSTART`（4001）即可，其机型类型会决定 `VEHICLE_TYPE=mc`。
**判据**：`control_allocator status`；若 `VEHICLE_TYPE=none`，会打 `No autostart ID found`（`rc.vehicle_setup:105`）。

### D. 通信段 `rcS:589-625`

| 行号 | 做了什么 |
|---|---|
| `:591-595` | **钩子④ `rc.board_mavlink`**（本板没有 ⇒ 跳过） |
| `:603` | `. rc.serial` —— **自动生成**（`Tools/serial/generate_config.py`），由 `default.px4board` 的串口声明驱动 |
| `:611` | `rc_input start`（必须在串口配置之后） |
| `:616-618` | `cdcacm_autostart`(`:616`) ⇒ 失败则 `sercon`(`:618`) + `mavlink start -d /dev/ttyACM0` |

**本板对应**：`boards/rm2027/fmu-h743/default.px4board:3` → `CONFIG_BOARD_SERIAL_TEL1="/dev/ttyS2"`；MAVLink 参数 `MAV_0_MODE`/`MAV_0_RATE` 等。
**判据**：`Starting MAVLink on /dev/ttyACM0`（`:619`）；之后 `mavlink boot_complete`（`:797`）⇒ QGC 显示已就绪。

---

## 4. 写 `rc.board_sensors` 时，这张表告诉你的四件事

1. **执行位置**：rcS 的 `:420`，大约是整份脚本的 **53%**（420/797）。
2. **它之前已经完成**：存储挂载（`:72-171`）→ **参数加载**（`:179-255`）→ **机型加载**（`:297-319`，`SYS_AUTOSTART` 已生效）
   ⇒ 所以你在这个文件里**可以放心依赖"参数已就绪、机型已确定"**（这正是能用 `-b` / `-R` 这类选项的前提）。
3. **它之后**才是：`rc.sensors`(`:428`) → `sensors start`(`:440`) → `ekf2`(`:446`) → `commander`(`:551`) → `dshot/pwm_out`(`:559-560`) → `control_allocator`(`rc.mc_apps:11`)
   ⇒ 你的驱动只要在 `:442` 之前把**模块**拉起来即可；**不要在启动脚本里等数据**。
4. **成功/失败判据**：
   - ✅ 出现 `Board sensors: /etc/init.d/rc.board_sensors` = 文件进了 ROMFS 且被执行
   - ❌ **没出现** ⇒ 问题在**构建期**（文件名不是白名单里的、没放在 `init/` 下），**不是脚本内容**
   - ⚠️ 出现了但传感器没数据 ⇒ 才是脚本/驱动的问题（用 `listener sensor_accel` 等事后查）

---

## 未核实 / 边界

- 表中"干了什么"是对 `rcS` 各段的**归纳**，非逐行翻译；`:1-18`、`:19-30` 等纯注释/变量初始化段我只标了作用。
- `rc.sysinit` 在本仓是 44 字节空壳（`ROMFS/px4fmu_common/init.d/rc.sysinit`），**是否有板/产品会往里写东西，未逐一核实**。
- 阶段划分依据是 rcS 内的注释横幅与命令顺序；`:19-56` 与 `:171-179` 两段的边界比其它段模糊，标的是近似区间。
