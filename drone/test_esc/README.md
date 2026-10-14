# test_esc —— F103 电调测试信号发生器

**一句话**：拿一块 **STM32F103** 冒充飞控，给电调发 **DShot**，同时把电调回的两路信号（**串口遥测** + **电流模拟量**）读回来。
这样**脱离飞控**就能把电调板的整个接口面测通。

分层：`Bsp/`（碰寄存器）→ `Module/`（纯协议，可在 PC 上单测）→ `App/`（状态机业务）。

```
App/app_esc_test.c      状态机：IDLE(3s 发 0 解锁) → RAMP(48→目标) → HOLD
App/app_debug.c         观测黑匣子 g_dbg（给 Ozone / OpenOCD 看）
Module/module_dshot.c   DShot 组帧（11 位值 + 遥测位 + CRC-4）
Module/module_kiss.c    KISS 遥测帧解析（10 字节 + CRC8 + 数值合理性筛）
Bsp/bsp_dshot_tx.c      DShot 波形：TIM3_CH1 + DMA 逐位改 CCR1
Bsp/bsp_uart_telem.c    收遥测：USART1 RX / PA10，115200 8N1
Bsp/bsp_current_adc.c   收电流模拟量：ADC1_IN1 / PA1，12 位
```

---

## 一、接线（★ 就这几根）

电调板上的信号座是 **U6**（`WAFER-GH1.25-4PWB`，4 脚）。**F1 与电调板必须共地**：

| F1 引脚 | 电调板 U6 | 信号 | 方向 |
|---|---|---|---|
| **PA6**（TIM3_CH1） | 第 **3** 脚 `ESC_DSHOT` | DShot 油门帧 | F1 → 电调 |
| **PA10**（USART1_RX） | 第 **2** 脚 `USART_TX` | KISS 遥测帧 115200 8N1 | 电调 → F1 |
| **PA1**（ADC1_IN1） | 第 **1** 脚 `ADC_IN1` | 电流模拟量（60 mV/A） | 电调 → F1 |
| **GND** | 第 **4** 脚 `GND` | 地 | —— |

> 引脚在代码里是可配置的宏：`Bsp/bsp_uart_telem.h` 的 `TELEM_UART_RX_PIN`、
> `Bsp/bsp_current_adc.h` 的 `CURRENT_ADC_PIN`。换脚记得连 `.c` 里的 GPIO 配置位一起改。

## 二、供电（要不要给电调供 VBAT？）

| 你想测什么 | 电调板供电 | 说明 |
|---|---|---|
| 通信链路：DShot 收得到吗 / 遥测回得来吗 / 电流线有电平吗 | **不需要 VBAT** | 电调 MCU 靠 ST-Link 的 3.3V 就够跑（已实测：TIM1 在跑、CR1=0x81）；`ADC_IN1` 会读到 ≈0 V（没有母线电流） |
| 真的转电机 | **需要 VBAT**，且**必须限流** | 先不装桨；第一版建议把 `APP_ESC_TEST_ENABLE_MOTOR` 设 0 只验协议，再打开 |

## 三、编译 / 烧写 / 观测

```bash
./build.sh                 # 编译
./build.sh flash           # 编译 + 烧写（默认 J-Link / SWD）
IFACE=stlink ./build.sh flash   # 换 ST-Link 烧
```

> ★ 烧写工具接的是**这块 F103**，不是电调板。
> J-Link 必须显式 `transport select swd`，否则 openocd 默认走 JTAG，会报
> `JTAG scan chain interrogation failed: all ones`。

**观测靠 `g_dbg`**（`App/app_debug.h`），没有串口打印：
- Ozone：打开 `test_esc.jdebug`，在 Watch 里敲 `g_dbg`；
- 命令行：`openocd ... -c "halt" -c "mdw 0x200001fc 30"`（地址以 `arm-none-eabi-nm build/Debug/test_esc.elf | grep g_dbg` 为准）。

### 关键观测项与判据

| 字段 | 看什么 |
|---|---|
| `loop_count` / `now_ms` | 任务在跑吗（1 kHz） |
| `state` / `throttle_cmd` / `frame` | 状态机走到哪、发出去的 16 位帧对不对 |
| `ccr_buf[16]` | 波形对不对：每个 bit 应只有 180（'1'）或 90（'0'）两种值 |
| `tx_sent` / `tx_drop` | 发出多少帧 / 因忙丢了多少（应恒为 0） |
| `telem_req_sent` | 我们请求了几次遥测（每 20 帧一次 = 50 Hz） |
| **`telem_rx_bytes`** | **收遥测的线接上了吗**（不涨 = 线没接/接错脚） |
| **`telem_frames_ok`** | **遥测解出来了吗**（字节在涨但这里不涨 = 波特率/极性/共地问题） |
| `telem_temp_c/volts_cV/current_cA/erpm_x100` | 电调报文（注意单位：0.01 V / 0.01 A / 100 eRPM） |
| `telem_frame[10]` | 帧同步不上时，肉眼看一眼原始字节 |
| `adc_raw / adc_mv / adc_current_cA` | 电流模拟量；与 `telem_current_cA` **应当一致**（同一颗 INA240 的两条路） |

## 四、可调宏

| 宏 | 位置 | 默认 | 含义 |
|---|---|---|---|
| `APP_ESC_TEST_ENABLE_MOTOR` | `App/app_esc_test.h` | 1 | 1 = 走完整流程（**会真的转电机**）；0 = 只发 disarm/beep 验协议 |
| `APP_ESC_TEST_RAMP_TARGET` | `App/app_esc_test.h` | 400 | 斜坡目标油门（0..2047） |
| `TELEM_REQ_EVERY` | `App/app_esc_test.c` | 20 | 每多少帧请求一次遥测 |
| `CURRENT_MILLIVOLT_PER_AMP` | `Bsp/bsp_current_adc.h` | 60 | 3 mΩ × 20 V/V |
| `CURRENT_OFFSET_MV` | `Bsp/bsp_current_adc.h` | 0 | INA240 REF 接 GND ⇒ 单向零点 0 V |

---

## 五、已经踩过的坑（别再踩）

1. **DShot CRC 输入是 12 位 packet**，不是 11 位值。早期版本少算了 `(v>>8)` 项，症状极其反直觉：
   油门 0 的帧电调接受（全零帧 CRC 恒为 0，怎么算都对），**非零油门一律被拒**。
   现已逐值核对 AM32 解码器：2048 值 × 2 遥测位 = **4096 帧全通过**。
2. **帧首要补一个空闲值 0**：定时器自由运行，DMA 被武装那一刻相位随机，第一个搬运会落在残缺周期里。
3. **发完必须清 `CCR1`**：否则 CCR 停在最后一位的值，帧间没有低电平空隙 ⇒ 电调跨帧数边沿 ⇒ 整帧错位。
4. **必须关掉 `CC1PE` 预装载**：否则每个比较值晚一个周期生效 ⇒ 帧长少一位（实测 50.0 µs）。
5. **J-Link 走 SWD** 要显式 `transport select swd`。

## 六、实测验证记录（2026-10-06）

### 6.1 单机验证（电调板由 ST-Link 3.3V 供电，未接 VBAT；J-Link 接 F103）

- **DShot 发送**：`tx_sent` 与 `loop_count` 同步增长、`tx_drop=0`；
  状态机数学与实测一致（`ms_in_state=1369` ms 时 `throttle_cmd=208`＝ 48 + 352×1369/3000 ✓）；
  `frame=0x1A0B` 的 CRC 手算复核一致 ✓。
- **ADC 链路**：把采样通道临时切到内部 **VREFINT**（通道 17，需 `CR2.TSVREFE=1` + 采样时间 ≥5.1 µs）
  ⇒ 读到 **1200 mV**（F1 典型值 1.20 V）⇒ 时钟分频（12 MHz）、校准、通道选择、换算、平均全部正确 ✓。
- **串口**：寄存器回读 `BRR=0x271`(=625，72 MHz/115200 整除)、`CR1=0x2024`(=UE|RE|RXNEIE)、
  `GPIOA->CRH` 中 PA10 半字节 = 4（浮空输入）✓；KISS 解析器主机侧单测：
  干净帧与"前置 200 字节噪声"两种情况都能解出准确值，无假阳性 ✓。

### 6.2 三线接全后的端到端验证（同一天，接上 U6 的 1/2/3 脚 + 共地）

**① F1 → 电调（DShot）**：电调侧（AM32 变量，经 ST-Link 读）
`dshot_goodcounts` 持续增长、`dshot_badcounts=0`、`inputSet=1`、`signaltimeout=2`（小=有信号）；
捕获定时器 `TIM3`：`CR1=1`(CEN)、`CCER=0xB`(双向沿捕获)、`CCMR1=0x41`、`ARR=0xFFFF`；
`DMA1_CH1 CCR=0x98b`、`out_put=0`（引脚处于输入模式，没被切成 EDT 发送模式）✓

**② 电调解锁**：干净复位后等 2.2 s（F1 正在发"油门 0"），读得 **`armed=1`** ⇒ **LED 转绿** ✓
（AM32 的 LED 只有两态：初始化完=红 `main.c:1855`；解锁=绿 `main.c:1371`）

**③ 电调 → F1（KISS 遥测 + 电流模拟量）**：F1 侧 `g_dbg`
`telem_rx_bytes=11470`、`telem_frames_ok=1147`、`telem_req_sent=1125`（≈1:1）、
`telem_err_count=0`、`telem_bad_value=0`；
解出 32 ℃ / 2.91 V / 0.04 A / 0 mAh / 800 eRPM（无 VBAT 时的合理值）；
电流模拟量 `adc_raw=26 → 21 mV → 0.35 A`（也是 ≈0）✓

> **零点偏差**：无母线电流时，模拟路读 21 mV（≈0.35 A）、遥测路读 4 mV（≈0.04 A）。
> 两者都接近 0，但模拟路有 ~20 mV 的零点偏移（ADC + 两地之间的地电位差）。
> 要精确测小电流，把 `CURRENT_OFFSET_MV` 设成实测零点即可。

### 6.3 ★ 一个会让人误判成"电调坏了"的坑：红灯

**现象**：电调上电后 LED 一直红，不像"初始化完成"。
**真相**：AM32 应用里只有两种 LED 状态 —— **红 = 已初始化但未解锁**，**绿 = 已解锁(ARMED)**。
所以"初始化完该亮绿灯"这个预期不对；绿灯要满足解锁条件（`Src/main.c:1358-1371`）：

```
!armed && cell_count==0 && inputSet && adjusted_input==0
        && armed_timeout_count > 1 秒(LOOP_FREQUENCY_HZ) && zero_input_count > 30
```

⇒ **信号必须被正确解码，且油门要持续为 0 约 1 秒以上。**

**测试时最容易踩的**：如果电调是在测试台已经进入 `RAMP/HOLD`（油门非 0）**之后**才上电/复位，
它就永远等不到"0 油门持续 1 秒" ⇒ 永远红灯。做法：**复位/上电电调时，保证测试台处在最前面那段
`IDLE`（发 0）里** —— 最简单就是"先复位测试台，紧接着复位电调"。

（另：用 SWD 直烧 app 后，bootloader 那个"跳转标志字节"有时会失效 ⇒ 电调其实停在 bootloader
里没跑 app，这时所有外设寄存器都是 0、LED 保持上次的颜色，看起来也像"坏了"。
判据：`pc` 落在 `0x08001xxx~0x0800Fxxx` 才是 app，见 `work/ESC-bootloader-不跳app-根因与修复.md`。）
