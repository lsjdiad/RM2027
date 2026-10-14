# 上电到飞行：执行主线

> **本篇是整套 code-twin 的主线。** 读它的时候请一直问自己同一个问题：
> **"此刻 CPU 在哪、下一条指令跳到哪、我示波器/串口上看到的现象由谁产生。"**
>
> 所有行号都可以直接跳过去看，不用自己翻。

---

## 0. 先看一张图：一上电，控制权交接四次

```
T0  ┌─ 复位向量            CPU 从 0x08000000 取第一条指令
    │
T1  ├─ ① bootloader        128 KB @ 0x08000000
    │                       只干三件事：初始化最小硬件 / 校验并跳 app / 提供上传通道
    │                       ↓ 【跳转】把向量表切到 app，跳过去
T2  ├─ ② NuttX 内核        @ 0x08020000（app 区）
    │                       把向量表重定位（VTOR），起 RTOS
    │                       ↓ 【进入 shell】CONFIG_INIT_ENTRYPOINT = "nsh_main"
T3  ├─ ③ nsh_main()        NuttX 的 shell
    │                       先跑板级 C 初始化，再跑启动脚本
    │                       ↓ 【执行脚本】CONFIG_NSH_SYSINITSCRIPT → rc.sysinit → rcS
T4  ├─ ④ rcS（脚本编排）    ★ 你真正要精通的一层
    │                       按固定顺序把 module 一个个拉起来
    │                       ↓ 【模块自己跑起来】
T5  └─ ⑤ 各 module          sensors → ekf2 → commander → mavlink → …
                            到这里系统才"能飞"
```

**★ 记住这条：`make` 只产出镜像，**上电顺序由上面这五个阶段决定**，`make` 一步都没参与。**

---

## 1. T0：复位向量 —— CPU 的第一条指令

**硬件事实（不用记，知道在哪查就行）：**
```
STM32H743 的 boot 引脚决定从哪取向量表
本板 flash 从 0x08000000 开始，所以复位后 CPU 读 0x08000000 处的两个字：
    第 1 个字 → 初始栈指针（SP）
    第 2 个字 → 复位处理函数地址（PC）
```
**⇒ 这个"前两个字"的约定贯穿全线** —— bootloader 判定"app 是否有效"用的就是它（见 §2）。

**🔗 想深入**：`[01_extracted/stm32/00-reset-clock-peripherals](../01_extracted/stm32/00-reset-clock-peripherals.md)`（描述 H743 的 boot 引脚与 VTOR 机制）

---

## 2. T1：① bootloader —— 128 KB @ `0x08000000`

**它的地盘（实测自本板链接脚本）：**
```
0x08000000 - 0x0801FFFF   128 KB    bootloader
   出处: boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld:113
         flash (rx) : ORIGIN = 0x08000000, LENGTH = 128K
```

### 2.1 它只干三件事

| # | 干什么 | 代码位置 |
|---|---|---|
| 1 | 初始化最小硬件（时钟、串口/USB、LED） | `platforms/nuttx/src/bootloader/stm/stm32_common/main.c` |
| 2 | **校验 app 镜像 → 有效就跳过去** | `bl.c` 的 `first_word` 机制（见下） |
| 3 | **提供"把新固件写进 flash"的通道**（串口 / USB 上传） | `bl.c` + `lib/uart.c` / `lib/cdcacm.c` |

### 2.2 ★ 它怎么决定"跳不跳"—— 这是全线最关键的一个判断

**bootloader 检查 app 向量表的第一个字（= app 的初始栈指针）：**
```
有效值       ⇒ 跳 app
0xffffffff   ⇒ 判"app 无效" ⇒ 【留在 bootloader 等重刷，永不跳半成品】
   出处: platforms/nuttx/src/bootloader/common/bl.c:317-318（检查）
         bl.c:629（初值设为 0xffffffff）
```

**写入时机（★ 这是"防变砖"的核心设计）：**
```
【全部数据写完 + 状态序列合法 + 收到 PROTO_BOOT 之后，作为最后一步才写】
   出处: bl.c:1113 / bl.c:1118
写完【立即读回校验】，不过就 cmd_fail
   出处: bl.c:1076 / bl.c:1121
```
**⇒ 效果：掉电只会导致"首字仍是 0xffffffff"⇒ 停在 bootloader ⇒ **永远不会跳一个写了一半的固件**。**

### 2.3 跳转动作本身

```
jump_to_app()   【定义在 ① bl.c:308】 但【调用在 ② main.c:771 / main.c:824】
                ⇒ ① 层的 bl.c 根本不知道"该不该跳"，它只在 bootloader() 返回时宣布"该跳了"（bl.c:1134）
跳之前会调用 arch_setvtor(...) 把向量表切到 app
                ⇒ platforms/nuttx/src/bootloader/stm/stm32_common/main.c:457
```

### 2.4 ⚠️ 你在台架上只能看到什么（**这条最实用**）

**bootloader 里没有 `printf`。** 唯一输出是两样：
```
① LED（本板 LED 语义）:
     ~10 Hz 闪 = 空闲等主机      bl.c:447-449（50 tick 翻转）+ bl.c:640
     常亮      = 正在擦除        bl.c:772
     灭        = 擦完            bl.c:782
     恢复闪    = 校验通过继续等  bl.c:795
② 串口的【二进制协议应答】（不是文字）
     cout(buf,len) @ bl.c:231 → usb_cout(bl.c:236) / uart_cout(bl.c:243)
```

**⇒ 所以台架上判断 bootloader 状态只有三条路：看灯 / 走它的串口协议 / 用调试器读寄存器。**
**（本项目实测：我们最后就是靠 SWD 读 RAM 才判定了电调 bootloader 的状态。）**

**🔗 完整决策序**：`[PX4-bootloader主流程时序图](../../PX4-bootloader主流程时序图.md)`（197 行，71+29 个行号已回验）

---

## 3. T2：② NuttX 内核 —— app 区 @ `0x08020000`

**app 的地盘：**
```
0x08020000 - 0x081DFFFF   1792 KB   app
   出处: boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:113
最后 128 KB（0x081E0000 - 0x081FFFFF）【让给 flash 参数存储】
   出处: 同上脚本 :113 的行内注释
```

**交接动作：**
```
① bootloader 调 arch_setvtor() 把 VTOR 指向 app 的向量表
② 跳到 app 的复位处理函数
③ NuttX 内核开始跑：初始化内核 → 建立工作队列/任务 → 挂载 ROMFS
   ⇒ 本板的最终配置在 build/rm2027_fmu-h743_default/NuttX/nuttx/.config
```

**🔗 想深入**：`[01_extracted/nuttx/00-poweron-chain](../01_extracted/nuttx/00-poweron-chain.md)`

---

## 4. T3：③ `nsh_main()` —— shell 接手，并跑板级 C 初始化

**为什么是 shell 接手（★ 这是"为什么真机没有 `main()`"的答案）：**
```
本板 nuttx-config/nsh/defconfig:116
    CONFIG_INIT_ENTRYPOINT="nsh_main"
⇒ NuttX 内核起来后直接进 nsh_main，不是进某个 main()
⇒ 【真机的"main"就是 shell 脚本 rcS 本身】
   出处: boards/rm2027/fmu-h743/nuttx-config/nsh/defconfig:116
```

**nsh 接手后干的第一件事是跑板级 C 代码：**
```
board_app_initialize()   ← boards/rm2027/fmu-h743/src/init.c:157
    └─ px4_platform_init()   (:160)
它的官方注释（boards/ark/fmu-v6x/src/init.c:40 同款）:
    "Code here is run before the rcS script is invoked"
    ⇒ ★【板级 C 初始化，早于 rcS】
```

**⇒ 这条决定了 25 个板级文件里那 10 个 `src/*.c` 的执行位置：它们在 rcS 之前。**

**🔗 想深入**：`[01_extracted/nuttx/nsh-and-rcS](../01_extracted/nuttx/nsh-and-rcS.md)`

---

## 5. T4：④ `rcS` —— 脚本编排层（**你要精通的就是这一层**）

### 5.1 脚本链（★ 三层，别只记 rcS）

```
nsh_main
   ↓ CONFIG_NSH_SYSINITSCRIPT = "init.d/rc.sysinit"    ← nshlib 编译期默认
   ↓    出处: platforms/nuttx/NuttX/apps/nshlib/nsh.h:295-296
   ↓          build/rm2027_fmu-h743_default/NuttX/nuttx/.config:2094
   ↓  rc.sysinit（本仓是 44 字节空壳: ROMFS/px4fmu_common/init.d/rc.sysinit）
   ↓
   ↓ CONFIG_NSH_INITSCRIPT = "init.d/rcS"              ← 同一个头文件的 :299-300
   ↓    路径 = CONFIG_ETC_ROMFSMOUNTPT + "/" + 该键（nsh.h:307）
   ↓
   rcS  ★ 700 行，真正的编排
```

### 5.2 rcS 的阶段（**五个板级钩子插在这里**）

| 阶段 | rcS 行 | 干什么 |
|---|---|---|
| 早期 | `:64` | **`rc.board_early`**（本板**没有**此文件 ⇒ 静默跳过） |
| 参数就绪 | `:278` | **`rc.board_defaults`** ★（本板有） |
| 存储/机型 | `:580` | `. rc.vehicle_setup` → 按 `SYS_AUTOSTART` 加载机型（4001 = Generic Quadcopter） |
| **传感器** | **`:420`** | **`rc.board_sensors`** ★（本板有）—— 拉起本板传感器 |
| 传感器（通用） | `:428` | `. rc.sensors`（上游通用脚本） |
| 传感器模块 | `:440` | **`sensors start`** ← ★ 真正的 sensors 模块在这里才启 |
| MAVLink | `:591` | **`rc.board_mavlink`**（本板**没有** ⇒ 静默跳过） |
| 末期 | `:693` | **`rc.board_extras`** ★（本板有） |

**★ 关键认知：`rc.board_sensors`（`:424`）和 `rc.sensors`（`:428`）只是"把驱动模块拉起来"，真正的 `sensors` 模块在 `:440` 才启。**

### 5.3 本板只提供 3 个钩子（实测）

```
boards/rm2027/fmu-h743/init/  只有:
    rc.board_defaults     ← 参数默认值
    rc.board_sensors      ← ★ 传感器驱动拉起
    rc.board_extras       ← 收尾
⇒ 另两个（rc.board_early / rc.board_mavlink）本板没有
   运行时 if [ -f ] 判空后【静默跳过、不报错】
```

**⇒ 判据：开机 console 打出 `Board sensors: /etc/init.d/rc.board_sensors` ⇔ 文件进了 ROMFS 且被执行。**
**⇒ 没有这一行 ⇒ 问题在【构建期】（文件名/路径/白名单），不是脚本内容。**

**🔗 完整阶段表**：`[PX4-rcS执行时序表](../../PX4-rcS执行时序表.md)`（173 行，109 个行号已回验）

---

## 6. T5：⑤ 各 module 跑起来

**从 rcS 往后，系统就靠 uORB 总线上的发布/订阅互相喂数据了：**
```
sensors 模块  → 读驱动 → 发布 sensor_combined / sensor_gyro / sensor_accel …
ekf2          → 订阅这些话题 → 发布 vehicle_attitude / vehicle_local_position …
commander     → 管解锁、飞行模式    → 发布 vehicle_command / actuator_armed …
control_allocator → 订阅姿态/位置设定值 → 发布 actuator_motors
dshot 驱动    → 订阅 actuator_motors → 按 PWM_MAIN_FUNC* 映射 → 4 路输出
mavlink       → 与地面站通信
```
**⇒ 六条信息流的完整梳理见 `[02-sensor-flow](02-sensor-flow.md)`；module 层怎么理解见 `[03-module-map](03-module-map.md)`。**

---

## 7. 全景表：一个时刻一张图

| 时刻 | 谁在跑 | 关键入口 | 你能观察到什么 |
|---|---|---|---|
| T0 | CPU 从 0x08000000 取向量 | — | 无法观察 |
| T1 | **bootloader**（128K @ 0x08000000） | `bl.c` 的 `bootloader()` | **只有 LED**（~10Hz 闪=等主机） |
| T1→T2 | 跳 app | `arch_setvtor()` main.c:457 | LED 灭 / 串口无输出 |
| T2 | **NuttX 内核**（app @ 0x08020000） | 内核初始化 | 串口 console 开始有输出 |
| T3 | `nsh_main` | defconfig:116 | console 出现 nsh 提示 |
| T3 | **板级 C 初始化** | `init.c:157 board_app_initialize()` | 传感器总线被初始化（示波器可看 SPI/I2C 活动） |
| T4 | **rcS 脚本** | rcS:1-797 | console 逐行打印启动过程 |
| T4 | `rc.board_sensors` | rcS:420 → :424 | **`Board sensors: ...` 这一行** ★ |
| T4 | `sensors start` | rcS:440 | console 出现 sensors 相关输出 |
| T5 | 各 module | 各自 `*_main` | console 出现模块启动行 |
| T5 | 能飞 | — | 解锁后电机响应 |

---

## 8. 跳转：接下来读哪一篇

**按"执行顺序"往下（推荐）：**
1. **`[02-sensor-flow](02-sensor-flow.md)`** —— 系统跑起来之后，**数据是怎么流的**（六类传感器端到端）
2. **`[03-module-map](03-module-map.md)`** —— 那么多 module 是**怎么协同**的（uORB / 工作队列 / 启动依赖）
3. **`[04-params-map](04-params-map.md)`** —— 你在 QGC 里改的**每个参数背后发生了什么**
4. **`[00-build-walkthrough](00-build-walkthrough.md)`** —— 回到最前面：**这个镜像本身是怎么被编出来的**

**想钻某一层：**
- bootloader 内部 → `[02_code_twin/bootloader/bl-c](../02_code_twin/bootloader/bl-c.md)`、`[02_code_twin/bootloader/stm32-common-main-c](../02_code_twin/bootloader/stm32-common-main-c.md)`
- NuttX 启动机制 → `[01_extracted/nuttx/00-poweron-chain](../01_extracted/nuttx/00-poweron-chain.md)`
- H743 复位/时钟/VTOR → `[01_extracted/stm32/00-reset-clock-peripherals](../01_extracted/stm32/00-reset-clock-peripherals.md)`
- 本板 25 个文件各自的执行位置 → `[02_code_twin/board/](../02_code_twin/board/README.md)`

---

## 源码在哪（本篇只讲流程；代码与逐行解释已归位到 02 层）

> ★ **本篇每一条 `文件:行` 都能点** —— 它跳到 `02_code_twin/` 里对应的篇，代码旁边就是解释。
> 三层各司其职：**01 讲语法/机制通则 · 02 讲某个文件的行号在干什么 · 03 只讲流程**。

| 代码在 | 02 层的篇 |
|---|---|
| `02_code_twin/bootloader/00-overview.md` | [`02_code_twin/bootloader/00-overview.md`](../02_code_twin/bootloader/00-overview.md) |
