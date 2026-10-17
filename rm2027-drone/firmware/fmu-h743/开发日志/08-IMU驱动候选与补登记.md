# 08 · IMU 驱动候选与补登记（一次编进 6 个 SPI IMU 驱动）

> 建立：2026-09-30
> 任务：`.planning/2026-09-30-供电与子代理策略/task_plan.md` 第五节 T-A / T-B（纯软件，不需要板子）
> 前情：`419f4ba` 是上一个子代理**被中断**时留下的未完成改动（commit message 明确写了
> "当前状态不自洽、不要拿去编译"）—— `default.px4board` 列了 6 个 IMU 驱动，
> 但 `src/spi.cpp` 只登记了 1 个 ⇒ 缺 5 行。本文把这 5 行补上并**真编过**，把 WIP 收尾。

---

## 零、一句话结论

```text
SPI1 的 6 个候选 IMU 驱动已【全部登记 + 全部编入固件 + 已逐字节核对链接结果】，
编译 EXIT=0、产出 .px4。上电后按本文第七节的 6 条命令逐个 start，
哪条打印 "<驱动> #0 on SPI bus 1" 就说明那颗 IMU 是哪个型号。
```

---

## 一、5 问（按 `开发日志/README.md` 规则）

### 1. 输入是什么

| 输入 | 路径 / 位置 |
|---|---|
| 板级 SPI 总线表 | `boards/rm2027/fmu-h743/src/spi.cpp`（本次唯一改动的源码文件） |
| 驱动开关 | `boards/rm2027/fmu-h743/default.px4board:14-19`（6 行，419f4ba 已加，本次未改） |
| 硬上限 | `platforms/common/include/px4_platform_common/spi.h:54` `#define SPI_BUS_MAX_DEVICES 6` |
| devtype 常量表 | `src/drivers/drv_sensor.h:72-197` |
| 逐驱动实现 | `src/drivers/imu/{invensense/icm42688p,invensense/icm42605,invensense/icm42670p,invensense/icm45686,bosch/bmi270,st/lsm6dsv}/` |
| 器件身份证据 | `06-IMU起不来-软件侧排查.md`（0x75 可读可写、复位读 0x00）、`07-总线没注册是误判.md` |

### 2. 怎么得到的（可复现的命令）

```bash
cd ~/桌面/RM2027/PX4-Autopilot        # = /home/xien/RM2027/PX4-Autopilot（符号链接，同一棵树）

# ① 硬上限自己核实（不信转述）
sed -n '54p' platforms/common/include/px4_platform_common/spi.h
grep -n "devices\[SPI_BUS_MAX_DEVICES\]" platforms/common/include/px4_platform_common/spi.h

# ② devtype 常量名（★ 不是照抄 42688 那行）
grep -n "DRV_IMU_DEVTYPE" src/drivers/drv_sensor.h

# ③ 参考真实使用该驱动的板子怎么登记
for d in ICM42605 ICM42670P ICM45686 BMI270 ST_LSM6DSV; do
  grep -rn "DRV_IMU_DEVTYPE_$d" boards/ --include=spi.cpp | grep -v rm2027; done

# ④ 命令名从 build 系统取（不是猜）
grep -o 'MODULE_NAME=\\"[a-z0-9_]*\\"' build/rm2027_fmu-h743_default/build.ninja | sort -u

# ⑤ 编译（单实例！）
make rm2027_fmu-h743_default

# ⑥ 核对链接结果（见第四节）
arm-none-eabi-objdump -t build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.elf | grep px4_spi_buses
```

### 3. 提取到的原始信息

**（a）硬上限 = 6，且板级不可覆盖**

```c
// platforms/common/include/px4_platform_common/spi.h:54
#define SPI_BUS_MAX_DEVICES 6
struct px4_spi_bus_devices_t {
	px4_spi_bus_device_t devices[SPI_BUS_MAX_DEVICES];   // ← 就是 6
};
```

`initSPIBus(Bus, const px4_spi_bus_devices_t &)` 收的就是这个定长数组
（`platforms/nuttx/src/px4/stm/stm32_common/include/px4_arch/spi_hw_description.h:64`）
⇒ **多写第 7 行是编译错误**，不是运行期截断。所以「6 个候选」正好占满，不能再加。

**（b）6 个 devtype 的准确名字（`src/drivers/drv_sensor.h`）**

| 驱动 | Kconfig 符号 | devtype 常量 | 值 | WHO_AM_I 寄存器 | 期望值 |
|---|---|---|---|---|---|
| Invensense ICM-42688-P | `DRIVERS_IMU_INVENSENSE_ICM42688P` | `DRV_IMU_DEVTYPE_ICM42688P` | 0x26 | 0x75（需切 bank0） | 0x47（`-6` 时 0x44） |
| Invensense ICM-42605 | `..._ICM42605` | `DRV_IMU_DEVTYPE_ICM42605` | 0x29 | 0x75 | 0x42 |
| Invensense ICM-42670-P | `..._ICM42670P` | `DRV_IMU_DEVTYPE_ICM42670P` | 0x2A | 0x75 | 0x67 |
| Invensense ICM-45686 | `..._ICM45686` | `DRV_IMU_DEVTYPE_ICM45686` | 0x34 | **0x72** | 0xE9 |
| Bosch BMI270 | `DRIVERS_IMU_BOSCH_BMI270` | `DRV_IMU_DEVTYPE_BMI270` | 0x37 | **0x00**（CHIP_ID） | 0x24 |
| ST LSM6DSV | `DRIVERS_IMU_ST_LSM6DSV` | ★ `DRV_IMU_DEVTYPE_ST_LSM6DSV` | 0x12 | **0x0F** | 0x70 / 0x73 / 0x75 |

> ★ **最容易踩的坑**：LSM6DSV 的常量名带 `ST_` 前缀 ——
> `DRV_IMU_DEVTYPE_ST_LSM6DSV`（`drv_sensor.h:73`），
> **没有** `DRV_IMU_DEVTYPE_LSM6DSV` 这个东西。照抄 `_ICM42688P` 的形状会写出不存在的符号。
> 依据：`lsm6dsv_main.cpp:78` 传的就是 `DRV_IMU_DEVTYPE_ST_LSM6DSV`。

**（c）参考板登记写法（6 个驱动全都只用 `initSPIDevice(devtype, CS[, DRDY])`）**

```text
ICM42605  boards/px4/fmu-v6u/src/spi.cpp:43     CS+DRDY ｜ boards/matek/h743:52 只 CS
ICM42670P boards/px4/fmu-v6x/src/spi.cpp:89     CS+DRDY ｜ boards/cbunmanned/h753-som:40 CS+DRDY
ICM45686  boards/px4/fmu-v6x/src/spi.cpp:136    CS+DRDY（各参考板都带 DRDY）
BMI270    boards/micoair/h743-v2/src/spi.cpp:45 CS+DRDY ｜ boards/micoair/h743:43 / corvon/743v1:43 **只 CS**
LSM6DSV   boards/px4/fmu-v6c/src/spi.cpp:44     CS+DRDY ｜ boards/ark/fmu-v6xrt:54 CS+DRDY
```

⇒ **没有哪个驱动的登记写法是特殊的**（Bosch / ST 也一样）。
差别只在 **DRDY 给不给**，而 6 个驱动**都支持不给**：

```cpp
// 例：icm42688p/ICM42688P.cpp:451 / bmi270/BMI270.cpp:606 / lsm6dsv/LSM6DSV.cpp:698
if (_drdy_gpio == 0) {
	// 退回定时器调度采样（ScheduleOnInterval），不挂中断
}
```

本板原理图有 `GYRO_INT1 = PD6`，所以 6 行**统一给 DRDY**，与原来那一行 `icm42688p` 完全一致
⇒ 变量只有 devtype 一个。

**（d）DRDY 不会造成"试错后留脏"（本次专门查过）**

```text
① probe()（只读 WHO_AM_I）发生在建立设备节点【之前】
   src/lib/drivers/device/nuttx/SPI.cpp:111  int ret = probe();
② probe 失败 ⇒ init() 失败 ⇒ 实例被 delete
   platforms/common/include/px4_platform_common/i2c_spi_buses.h:365-368
③ DRDY 的 EXTI 只在 RunImpl 里挂（各驱动 DataReadyInterruptConfigure）
   icm42688p:212 / icm42605:172 / icm42670p:164 / icm45686:201 / bmi270:611 / lsm6dsv:703
   ⇒ 失败的实例根本进不到 Run，不会在 PD6 上留下中断
```

唯一副作用：Invensense 那 4 个驱动的 probe 会先写一次 `REG_BANK_SEL(0x76)`
（`ICM42688P.cpp:131 SelectRegisterBank(..., true)`）。对非同族芯片就是"往某个未知寄存器写了 1 字节"，
无害；不放心可以 `reboot` 一次复位芯片。

### 4. 据此决定了什么（落点）

**`boards/rm2027/fmu-h743/src/spi.cpp`** —— `px4_spi_buses[0]`（SPI1）从 1 个 device 扩到 **6 个**，
每行一个候选，**CS 全部 `SPI::CS{GPIO::PortB, GPIO::Pin4}`、DRDY 全部 `SPI::DRDY{GPIO::PortD, GPIO::Pin6}`**：

```cpp
initSPIDevice(DRV_IMU_DEVTYPE_ICM42688P,  SPI::CS{GPIO::PortB, GPIO::Pin4}, SPI::DRDY{GPIO::PortD, GPIO::Pin6}),
initSPIDevice(DRV_IMU_DEVTYPE_ICM42605,   SPI::CS{GPIO::PortB, GPIO::Pin4}, SPI::DRDY{GPIO::PortD, GPIO::Pin6}),
initSPIDevice(DRV_IMU_DEVTYPE_ICM42670P,  SPI::CS{GPIO::PortB, GPIO::Pin4}, SPI::DRDY{GPIO::PortD, GPIO::Pin6}),
initSPIDevice(DRV_IMU_DEVTYPE_ICM45686,   SPI::CS{GPIO::PortB, GPIO::Pin4}, SPI::DRDY{GPIO::PortD, GPIO::Pin6}),
initSPIDevice(DRV_IMU_DEVTYPE_BMI270,     SPI::CS{GPIO::PortB, GPIO::Pin4}, SPI::DRDY{GPIO::PortD, GPIO::Pin6}),
initSPIDevice(DRV_IMU_DEVTYPE_ST_LSM6DSV, SPI::CS{GPIO::PortB, GPIO::Pin4}, SPI::DRDY{GPIO::PortD, GPIO::Pin6}),
```

**没改的东西**：`default.px4board`（6 行开关 419f4ba 已加，本次一字未动）、
`init/rc.board_sensors`、`src/board_config.h`、链接地址、bootloader 布局 —— 全未碰。

### 5. 有没有后悔药

```text
把 src/spi.cpp 里除第 1 行(ICM42688P)以外的 5 行删掉，
并把 default.px4board:15-19 那 5 行 CONFIG_DRIVERS_IMU_* 删掉（或改 =n），重编即可。
两处必须【同时】改：只改一处会出现「开关开着但没登记」或「登记了但没编进来」，运行时匹配不到。
本改动唯一改动文件：src/spi.cpp（+ 注释）；回退 = git checkout 该文件的一个 hunk。
```

---

## 二、为什么要把"6 个候选"一次编进去（而不是一次一个）

```text
一轮"改一行 → 重编 → 重烧 → 去 QGC 敲一条 → 看结果" ≈ 十几分钟，而且必须有板子在场。
6 个候选 = 6 轮 ≈ 1.5 小时，且每次都要用户守着。

一次编进 6 个之后：只需要【一次】重编重烧，之后在 QGC 的 MAVLink Console 里
连敲 6 条命令（每条几秒），答案就出来了。用户的时间成本从"6 轮"降到"6 条命令"。
代价：固件里多 5 个不用的驱动（FLASH 从 77.0% 涨到 78.19%，+约 12KB）。
```

**为什么只选这 6 个**：都是"135 脚 / 2.5×3mm LGA 附近这一档"的常见 SPI IMU，
且**封装/接口与本板对得上**。被排除的写在 `default.px4board:20-25` 的注释里
（`BMI088` 需要两条 CS，本板只有 PB4 一条 ⇒ 物理上不可能；`MPU6000`/`ICM20602` 封装对不上）。

---

## 三、补登记的来龙去脉（把 419f4ba 的 WIP 收尾）

```text
419f4ba（2026-09-29 19:10，被中断的子代理留下）
  · default.px4board  列了 6 个 CONFIG_DRIVERS_IMU_*  ✅ 这部分是对的
  · src/spi.cpp       只登记了 1 个 devtype           ❌ 缺 5 行
  ⇒ 后果：那 5 个驱动会被编进固件（有 <驱动> 命令、有 main 符号），
    但 SPI1 的设备表里没有它们的 devtype ⇒ SPIBusIterator 一个都匹配不到
    ⇒ 上电敲 `icm42605 -s -b 1 start` 只会得到 "no instance started"，永远试不出型号。
    commit message 自己写了"不自洽、不要拿去编译" —— 本次就是来补齐它。

已完成的收尾：
  · src/spi.cpp 补 5 行（+ 详细注释解释为什么 6 个、上限在哪、安全性依据）
  · 真编过一次（EXIT=0，产出 .px4）—— 见下节
  · 本文（开发日志 08）补齐 419f4ba 里点名"尚未创建"的那份日志
```

---

## 四、编译验证（T-B）—— 结果：通过

```text
命令：cd ~/桌面/RM2027/PX4-Autopilot && make rm2027_fmu-h743_default
       （单实例，无并发；全程只有一个 make 在跑）

结果：EXIT=0
       [1060/1061] Generating ../../rm2027_fmu-h743_default.bin
       [1061/1061] Creating .../rm2027_fmu-h743_default.px4
       FLASH: 1537336 B / 1920 KB = 78.19%   （扩前 77% 左右）
       产物：build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.px4  1,487,754 B
       日志：/tmp/rm2027-build-TB.log（1100 行）
       grep error / undefined reference → 零命中（没有出现旧归档 .a 那种假链接错误）
       6 个驱动 × (main + 驱动体) = 12 个 .obj 全部重新编译（日志 496~600 行）
```

### ★ 三道独立核对（不是"编过就算"）

**① 配置层**：boardconfig 里 6 个开关都在（证明 `.px4board` 那 6 行进 kconfig 了，
含行尾 `# 注释` 的写法能正确解析 —— kconfiglib 对 bool 只取 `=` 右侧第一个字符）：

```bash
grep -n "^CONFIG_DRIVERS_IMU" build/rm2027_fmu-h743_default/boardconfig
# 220 BMI270 / 233 ICM42605 / 234 ICM42670P / 235 ICM42688P / 236 ICM45686 / 263 ST_LSM6DSV  ✅ 6 个
```

**② 符号层**：6 个模块真的被链接进去了

```bash
nm build/.../rm2027_fmu-h743_default.elf | grep -c " T <xxx>_main"   # 6/6 各 1 个
# icm42688p_main / icm42605_main / icm42670p_main / icm45686_main / bmi270_main / lsm6dsv_main
```

**③ 数据层（最硬）**：直接 dump 固件里 `px4_spi_buses[0]` 的字节，逐字段核对

```bash
arm-none-eabi-objdump -t  ...elf | grep px4_spi_buses
#   0818ded8 g  O .text  00000270 px4_spi_buses      (0x270/6 条总线 = 每条 104 字节)
arm-none-eabi-objdump -s -j .text --start-address=0x0818ded8 --stop-address=0x0818df48 ...elf
```

```text
 818ded8 14010400 36010000 26000010 26000000   cs=0x40114 drdy=0x136 devid=0x10000026 devtype=0x26
 818dee8 14010400 36010000 29000010 29000000   → 0x29 ICM42605
 818def8 14010400 36010000 2a000010 2a000000   → 0x2A ICM42670P
 818df08 14010400 36010000 34000010 34000000   → 0x34 ICM45686
 818df18 14010400 36010000 37000010 37000000   → 0x37 BMI270
 818df28 14010400 36010000 12000010 12000000   → 0x12 ST_LSM6DSV
 818df38 00000000 01000000 00000000 00000000   power_enable=0, bus=0x01(=SPI1), topo=0, lock=0
```

逐位解码（依据 `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32_gpio.h`：
`GPIO_PORT_SHIFT=4 / GPIO_PIN_SHIFT=0 / GPIO_MODE_SHIFT=18 / GPIO_OUTPUT_SET=1<<8`）：

```text
cs   = 0x00040114 = PORTB(1<<4=0x10) | PIN4(4) | OUTPUT(1<<18=0x40000) | OUTPUT_SET(0x100)  ⇒ PB4  ✅
drdy = 0x00000136 = PORTD(3<<4=0x30) | PIN6(6) | EXTI(1<<8=0x100)                            ⇒ PD6  ✅
devid = 0x10000026 = PX4_SPIDEV_ID(PX4_SPI_DEVICE_ID(0x1000), 0x26)                            ✅
后 5 条总线：bus 字段 = 0xff(= -1)（`px4_spi_bus_t::bus{-1}` 默认值）⇒ 未用，不会和别人抢 bus 号 ✅
```

**额外收获**：`validateSPIConfig` 是**编译期** `constexpr_assert`，要求
「NuttX 里开了的 SPI 总线必须在表里声明，反过来说没声明的不能开着」
（`platforms/nuttx/src/px4/stm/stm32h7/include/px4_arch/spi_hw_description.h:39-88`）。
本板 NuttX 只开了 `CONFIG_STM32H7_SPI1=y`（SPI2/3/4/6 显式 not set）
⇒ 只声明 SPI1 是正确的，且**这次编译通过本身就证明了这一点**。

---

## 五、上电后"挨个试 IMU"的命令清单（T-C）

> 前置：用第五节 T-B 产出的固件**重烧一次**（本次未烧，板子断电中）。
> 位置：QGC → MAVLink Console（或 NSH 串口）。**每条之间等 1~2 秒。**

### 5.1 六条命令（顺序有讲究，见 5.4）

```sh
icm45686   -s -b 1 -R 0 start     # WHO_AM_I @0x72 期望 0xE9   ← 先试"读别的地址"的
bmi270     -s -b 1 -R 0 start     # CHIP_ID  @0x00 期望 0x24
lsm6dsv    -s -b 1 -R 0 start     # WHO_AM_I @0x0F 期望 0x70
icm42670p  -s -b 1 -R 0 start     # WHO_AM_I @0x75 期望 0x67
icm42605   -s -b 1 -R 0 start     # WHO_AM_I @0x75 期望 0x42
icm42688p  -s -b 1 -R 0 start     # WHO_AM_I @0x75 期望 0x47（原理图标称值，上一轮已试过失败）
```

每条失败后先清干净再试下一条：

```sh
<刚试的那个驱动> stop          # 例：bmi270 stop
```

### 5.2 怎么判读（结果文字来自源码，不是猜的）

| 看到什么 | 含义 | 依据 |
|---|---|---|
| `<驱动> #0 on SPI bus 1` | ★ **命中** = 那颗 IMU 就是这个型号 | `platforms/common/i2c_spi_buses.cpp:744` `PX4_INFO_RAW("%s #%i on SPI bus %d", ...)` |
| `ERROR [<驱动>] <驱动>: no instance started (no device on bus?)` | 这个驱动的 WHO_AM_I 对不上（**不是**"总线没注册"，见 5.3） | 同文件 `:764-772`（internal 总线走 `PX4_ERR`；只有 external 才打 `WARN`） |
| 打印用法（usage）然后退出 | 选项拼错了（例如多打了 `-d` —— `-d` **不是合法选项**，见 `07-总线没注册是误判.md` E-3） | 各 `*_main.cpp` 的 getOpt 选项串 |

> 命令名在下表核对过（`build.ninja` 里的 `MODULE_NAME="<名字>"` = `cmake/px4_add_module.cmake:215` 由 `MAIN` 生成）：
> `icm42688p` / `icm42605` / `icm42670p` / `icm45686` / `bmi270` / `lsm6dsv` —— **6/6 与主文件名一致**。

### 5.3 为什么"失败 = 型号不符"，而不是"没登记上"

这是本次专门证明的，否则判读会含糊：

```text
① 6 个登记项确实在固件里（第四节：逐字节 dump 出来的）
② 匹配条件：SPIBusIterator 对 internal 总线要求 (a) 表里 bus == 1
   （platforms/common/spi.cpp:143 `_bus == bus_data.bus`）(b) devtype_driver == 驱动自己的 devtype（:154）
   ⇒ 我们 6 个 devtype 各不相同，各自只会匹配自己那一行
③ board_has_bus(BOARD_SPI_BUS, 1) 恒为 true：
   本板 **没有** 定义 BOARD_HAS_BUS_MANIFEST（`grep -r BOARD_HAS_BUS_MANIFEST boards/rm2027/` 零命中）
   ⇒ 走 platforms/common/include/px4_platform_common/board_common.h:1180 的
     `#define board_has_bus(t, b) true`（编译期常量 true）
④ 本板一条 external/shared SPI 总线都没有 ⇒ `-s`（internal）是唯一正确的写法，
   且必须写（`module_start` 里 `configuredBusOption()==All` 时直接报 "need to specify a bus type"）
⇒ 结论：6 条命令里任一条报 "no instance started"，只可能是 probe 的 WHO_AM_I 不匹配。
```

### 5.4 建议顺序的理由

```text
上一轮用调试器做过的寄存器级证据（06 号日志）：
  那颗芯片在 0x75 上【可读可写】，复位后读回 0x00 —— 而真的 ICM-42688-P 的 0x75
  是【只读】WHO_AM_I，必须读回 0x47。
⇒ 三个"从 0x75 读 ID"的 Invensense 驱动（42688P/42605/42670P）先天不被看好，
  所以先试"从别的地址读 ID"的三个：icm45686(@0x72) / bmi270(@0x00) / lsm6dsv(@0x0F)。
  它们都失败再回头试 0x75 那三个。
```

### 5.5 命中之后还要做的（★ 别把"ID 对上"当终点）

```text
① 确认真的有数据，而不只是 ID 对上（克隆片可能 ID 对、数据错）：
     listener sensor_gyro      # 看有没有频率、数值是否合理、静止时角速度≈0
     listener sensor_accel     # 静止时合矢量 ≈ 9.8 m/s²（朝向决定分量）
② 确认 devtype 与 RC/其他驱动无冲突：`sensors status`、`top`
③ 把结果（哪条命中 + `listener` 数值）回填给 Lead，再决定：
     · default.px4board 收窄到 1 个 CONFIG_DRIVERS_IMU_*
     · src/spi.cpp 删掉另外 5 行
     · init/rc.board_sensors:41 的 `icm42688p ...` 换成命中的那个驱动名
   ⚠️ 这三处必须【同时】改（见第一节 5「后悔药」）
   ⚠️ init/rc.board_sensors 属于"用户实测确认过"的文件 —— 改它必须用户/Lead 点头，本次未碰
```

---

## 六、顺手发现的问题（写下来，别丢）

### F-1 ★ `init/rc.board_sensors:27` 引用了一个**不存在的工具** `rm2027_spiid`

```text
文件原话（rc.board_sensors:26-27）：
  "取证工具与候选清单见 开发日志/08-*.md
   （命令行：`rm2027_spiid` —— 只读地把那颗片 0x00~0x7F 全 dump 出来）"

核实：
  grep -rn "rm2027_spiid" 全仓库 → 只命中 rc.board_sensors 这一处注释本身；
  build/rm2027_fmu-h743_default/build.ninja 里也搜不到 ⇒ 该命令**从未实现、也不在固件里**。

⇒ 这是一条悬空引用（上一个子代理的计划，没落地）。
⇒ 本次 T-A/T-B/T-C 的范围是"用 6 个现成驱动挨个试"，**没有**实现 rm2027_spiid（超出边界，
   且会再引入一次编译/模块注册改动）。
⇒ 建议（给 Lead 决策，我没有动 rc.board_sensors）：
   a) 要么把 rc.board_sensors:27 那句注释删掉/改写（它现在会误导下一个人去敲一个不存在的命令）；
   b) 要么把它做成真工具（新增一个只读 SPI dump 的 systemcmd，~50 行 + 一次重编）——
      这条路拿到的信息比"挨个试驱动"更硬（能直接看到 0x00~0x7F 的器件指纹）。
```

### F-2 `init/rc.board_sensors:41` 开机会先跑 `icm42688p ... start` 并必然失败

```text
不是新问题，但上电后一定会看到它报 "no instance started (no device on bus?)"。
那是**预期**的（型号不对），别误以为是这次改动引入的回归。
```

---

## 七、负结果 / 注意事项（省下一个人两小时）

| # | 想法 | 结论 | 依据 |
|---|---|---|---|
| N-1 | 把 6 个以上的候选都编进去 | ❌ 编不下 | `SPI_BUS_MAX_DEVICES == 6` 是 `#define`，板级不可覆盖；第 7 行直接编译错误 |
| N-2 | 每个候选给不同的 CS 来区分 | ❌ 无意义 | 硬件上 SPI1 只有一颗芯片、一条 CS(PB4)。给不同 CS 会去选不存在的片选 |
| N-3 | 不给 DRDY 更安全 | ⚪ 都一样 | 6 个驱动 DRDY 都是可选；本板有 PD6 就照着给，省得以后补 |
| N-4 | `-d` 能打印 WHO_AM_I 值 | ❌ 错（上一轮的错建议） | `BusCLIArguments` 组出的选项串里没有 `d`；见 `07` 号日志 E-3 |
| N-5 | 用 `-X`（external）试 SPI | ❌ 永远匹配不到 | 本板无 external/shared SPI 总线；`-s` 才对（同 07 号日志 I2C 那个坑的 SPI 版） |
| N-6 | 失败后再 `reboot` 清状态 | ⚪ 一般不必 | probe 只读 WHO_AM_I；只有 Invensense 那 4 个会先写一次 0x76（无害） |
| N-7 | `/dev/spi1` 不存在 ⇒ 总线没注册 | ❌ 误判 | 见 `07-总线没注册是误判.md`（4 条独立证据） |

---

## 八、文件与行号索引（下次直接跳）

| 内容 | 位置 |
|---|---|
| ★ 本次改动 | `boards/rm2027/fmu-h743/src/spi.cpp:46-100`（注释 46-86，6 行登记 87-100） |
| 6 个驱动开关 | `boards/rm2027/fmu-h743/default.px4board:14-19`（被挤掉的可换项：20-25） |
| 上限定义 | `platforms/common/include/px4_platform_common/spi.h:54` |
| 登记宏实现 | `platforms/nuttx/src/px4/stm/stm32_common/include/px4_arch/spi_hw_description.h:43,64` |
| 编译期总线一致性检查 | `platforms/nuttx/src/px4/stm/stm32h7/include/px4_arch/spi_hw_description.h:39-88` |
| 运行时匹配（internal） | `platforms/common/spi.cpp:135-163` |
| 启动成功/失败打印 | `platforms/common/i2c_spi_buses.cpp:744`（成功）/ `:764-772`（失败） |
| probe 时机 | `src/lib/drivers/device/nuttx/SPI.cpp:102-111` |
| `-s` / `-b` / `-R` 语义 | `platforms/common/i2c_spi_buses.cpp:197-212`（`-s`=internal，`-b`=总线号） |
| 命令名来源 | `cmake/px4_add_module.cmake:215`（`MODULE_NAME="<MAIN>"`） |
