# `loose` —— 代码孪生

> **层**：`02_code_twin/`（代码孪生）
> | 想看什么 | 去哪 |
> |---|---|
> | 驱动层机制 | [`01_extracted/`](../../01_extracted/) |

---

## 标注源码### `src/drivers/drv_dshot.h`
<a id="src-src-drivers-drv-dshot-h-116"></a>
**↓ 文档在讲这里：**[`src/drivers/drv_dshot.h:116`](loose.md#^src-src-drivers-drv-dshot-h-116)

```c
   113 │  * @param command	dshot_command_t
   114 │  * @param telemetry	If true, request telemetry from that motor
   115 │  */
▶  116 │ static inline void up_dshot_motor_command(unsigned channel, uint16_t command, bool telemetry)
   117 │ {
   118 │ 	dshot_motor_data_set(channel, command, telemetry);
   119 │ }
```
> **说明**：3 | wq:hp_default（优先级 -18） | 把归一化值映射成通道号 → DShot 帧 | MixingOutput::update() mixer_module.cpp:421 | 内部：_current_output_value[] | DShot::updateOutputs()（DShot.cpp:125） | ┃ 4 | hp_default | 打包成 DShot 位流 | up_dshot_motor_command()（声明 drv_dshot.h:116）+ up_dshot_trigger()（drv_dshot.h:124） | — | STM32 HAL 层（platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c） |
^src-src-drivers-drv-dshot-h-116

### `src/drivers/drv_dshot.h`
<a id="src-src-drivers-drv-dshot-h-124"></a>
**↓ 文档在讲这里：**[`src/drivers/drv_dshot.h:124`](loose.md#^src-src-drivers-drv-dshot-h-124)

```c
   121 │ /**
   122 │  * Trigger dshot data transfer.
   123 │  */
▶  124 │ __EXPORT extern void up_dshot_trigger(void);
   125 │ 
   126 │ /**
   127 │  * Arm or disarm dshot outputs (This will enable/disable complete timer for safety purpose.).
```
> **说明**：3 | wq:hp_default（优先级 -18） | 把归一化值映射成通道号 → DShot 帧 | MixingOutput::update() mixer_module.cpp:421 | 内部：_current_output_value[] | DShot::updateOutputs()（DShot.cpp:125） | ┃ 4 | hp_default | 打包成 DShot 位流 | up_dshot_motor_command()（声明 drv_dshot.h:116）+ up_dshot_trigger()（drv_dshot.h:124） | — | STM32 HAL 层（platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c） |
^src-src-drivers-drv-dshot-h-124
