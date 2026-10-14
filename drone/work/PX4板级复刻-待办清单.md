# PX4 板级复刻 · 待办清单（`boards/rm2027/fmu-h743/`）

> **用途**：从头自己复刻这块板（`boards/rm2027/fmu-h743/`，共 25 个文件）。
> **纪律**：本文**只给文件名 + 一句话说明它管什么 + 去哪查依据**；**不含任何代码/配置内容**。
> 复刻 = **自己写**；写不出来时按下面第 ④ 步去对照参照物，而不是把整份抄过来。

## 起点状态

- 你现在在复刻起点：分支 `learn/rm2027`（= `2c47a16`，与 `main` 同一个 commit，即**上游快照**）
- `boards/rm2027/fmu-h743/` 是**空**的 ⇒ 25 个文件都要自己写
- 你的成果在 `h104-protocol` / `teaching/*` 分支里（各 25 个文件），**那是对照用的"标准答案"**

## 自学自测流程

```bash
# ① 只拿清单（不泄露内容）
git ls-tree -r --name-only h104-protocol boards/rm2027/

# ② 自己写（照官方文档 + 芯片手册）

# ③ 随时自测"还差多少" —— ★ 这才是"标准答案"的正确用法
git diff --stat h104-protocol -- boards/rm2027/
#    变成空 ⇒ 你逐字节复现了

# ④ 真卡住了，才看某一个文件
git show h104-protocol:boards/rm2027/fmu-h743/src/spi.cpp
```

**结构参照物（抄结构、不抄内容）**：上游 `boards/matek/h743-slim/` 与本板**几乎 1:1**
（它多一个 `src/sdio.c`；我们多一个 `README.md`）—— 不知道"这块板该有哪些文件"时，就照它的目录看。

---

## 25 个文件待办表

| 文件 | 一句话：它管什么 | 依据（去哪查） |
|---|---|---|
| `README.md` | 这块板是什么、谁维护、怎么编译与烧写（给人看的） | `docs/en/hardware/board_support_guide.md:20` |
| `default.px4board` | 本板**编哪些驱动/模块**（"选择"层；与 Kconfig 配套） | `docs/en/hardware/porting_guide.md:19`、`docs/en/hardware/porting_guide_config.md:48`、`docs/en/dev_setup/building_px4.md` |
| `bootloader.px4board` | **bootloader** 那份固件的选型 | `docs/en/hardware/porting_guide_config.md`；模板板同名文件 |
| `firmware.prototype` | 固件**描述**（board_id / magic / 名称），给工具识别固件用 | 模板板同名文件（JSON 结构） |
| `init/rc.board_defaults` | 开机脚本：**板级默认参数** | `docs/en/hardware/porting_guide.md:20-23` |
| `init/rc.board_extras` | 开机脚本：**板级额外启动项**（非传感器） | `docs/en/hardware/porting_guide.md:21-23`；模板板同名文件 |
| `init/rc.board_sensors` | 开机脚本：**板载传感器怎么被拉起**（哪个驱动/哪条总线/什么方向） | `docs/en/hardware/porting_guide.md:20-23`、`docs/en/sensor_bus/` |
| `nuttx-config/Kconfig` | NuttX 层的**可选项声明** | `docs/en/hardware/porting_guide_nuttx.md:19`、`porting_guide_config.md:8` |
| `nuttx-config/nsh/defconfig` | **NuttX 内核配置**（UART/SPI/I2C/ADC/DMA/缓冲大小…） | `docs/en/hardware/porting_guide_nuttx.md:16,85` |
| `nuttx-config/bootloader/defconfig` | **bootloader 的 NuttX 内核配置** | `docs/en/hardware/porting_guide_nuttx.md:55` |
| `nuttx-config/include/board.h` | **NuttX 侧引脚与时钟**定义 | `docs/en/hardware/porting_guide_nuttx.md:14,86`；芯片手册 |
| `nuttx-config/include/board_dma_map.h` | **DMA 请求映射**（外设 ↔ DMA 通道/流） | 模板板同名文件；STM32H7 芯片手册 DMA 章节 |
| `nuttx-config/scripts/script.ld` | **主固件的链接脚本**（Flash/RAM 分区布局） | `docs/en/advanced_config/bootloader_secure_boot.md`；模板板同名文件 |
| `nuttx-config/scripts/bootloader_script.ld` | **bootloader 的链接脚本** | 同上；模板板同名文件 |
| `src/CMakeLists.txt` | 板级 **C++ 源文件清单** + 要链接的库 | `docs/en/dev_setup/building_px4.md`；模板板同名文件 |
| `src/board_config.h` | 板级**硬件常量**（总线数、片选/中断脚、ADC、定时器…） | `docs/en/hardware/porting_guide_nuttx.md:14`、`docs/en/hardware/serial_port_mapping.md` |
| `src/hw_config.h` | 板级**外设/接口的软件配置**（如 USB 上暴露哪个串口） | `docs/en/advanced_config/bootloader_secure_boot.md`；模板板同名文件 |
| `src/init.c` | **上电初始化**（时钟、GPIO、外设、参数存储挂载） | `docs/en/hardware/porting_guide_nuttx.md`；模板板同名文件 |
| `src/spi.cpp` | **SPI 总线登记 + 片选→器件型号登记**（谁挂在哪条总线） | `docs/en/sensor_bus/`；模板板同名文件 |
| `src/i2c.cpp` | **I2C 总线声明**（内部/外部、总线号） | `docs/en/sensor_bus/i2c_general.md`、`docs/en/sensor_bus/i2c_development.md` |
| `src/led.c` | **LED 驱动**（颜色与闪烁的含义） | `docs/en/getting_started/led_meanings.md`；模板板同名文件 |
| `src/usb.c` | **USB 的板级实现** | 模板板同名文件 |
| `src/timer_config.cpp` | **PWM / 定时器通道**的板级定义（输出按硬件定时器分组） | `docs/en/concept/control_allocation.md`、`docs/en/config/actuators.md:338-339`；模板板同名文件 |
| `src/bootloader_main.c` | **bootloader 入口 / 上传通道** | `docs/en/advanced_config/bootloader_update.md`；模板板同名文件 |
| `extras/rm2027_fmu-h743_bootloader.bin` | ❗**二进制产物**（预编译 bootloader，给上传流程用） | 上游同样惯例：`boards/matek/h743-slim/extras/matek_h743-slim_bootloader.bin`。**无法手写** ⇒ 要么从分支取、要么自己编 bootloader |

---

## 唯一例外

`extras/rm2027_fmu-h743_bootloader.bin` —— **二进制，没法手写**：

```bash
# 从分支取（其余 24 个请自己写）
git checkout h104-protocol -- boards/rm2027/fmu-h743/extras/rm2027_fmu-h743_bootloader.bin
```

**其余 24 个文件都是文本/脚本/配置，全部可以自己写。**
