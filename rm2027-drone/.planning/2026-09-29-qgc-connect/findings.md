# findings · 2026-09-29

## 硬件侧

```text
ST-Link V2 (0483:3748)  已连，能识别芯片
  chipid 0x450 = STM32H74x/H75x
  flash 2097152 (2MB)  sram 131072
  Target voltage 3.248663 V  ← 板子供电正常
USB-TTL CH340 (1a86:7523) → /dev/ttyUSB0
```

## 寄存器读数（2026-09-29 首次烧录后）

```text
USART3 (0x40004800)  CR1 = 0x00000000   ← 未启用
USART1 (0x40011000)  CR1 = 0x2000002d   ← 已启用（console）
USART1               ISR = 0x0de310fe   ← ORE=1 NE=1 FE=1
UART5  (0x40005000)  CR1 = 0x00000000   ← 未启用
NVIC ISER0 = 0x1003f800 / ISER1 = 0x1f008028  → IRQ37(=USART1) 常挂
```

**解读**：串口1 没接任何东西 → RX 悬空 → 持续帧错误 → 中断风暴 → 抢走 CPU。

## 关键认知

1. **"串口3没数据"的根因不在串口3，而在空着的串口1**。用户插的位置是对的。
2. NuttX 的 `/dev/ttySx` 编号 = 已启用 UART 的注册顺序。动 UART 使能开关会整体移位。
3. `platforms/nuttx/NuttX/nuttx/.config` 会被**最后一次构建**覆盖 ——
   读 app 的配置要读 `build/<board>_default/NuttX/nuttx/.config`。

## 待验证的假设（2026-09-29 16:41 已全部验证 ✅）

- [x] 去掉 console 后，USART3 的 CR1 会被 PX4 的 MAVLink 置位
      → ✅ `USART3 CR1 = 0x2000002d`（UE+RE+TE+RXNEIE）
- [x] MAVLink 的波特率是 57600（`SER_TEL1_BAUD`）
      → ✅ 电脑侧按 57600 收到合法 MAVLink v2 帧（含 HEARTBEAT）

## 根因修掉后的读数（2026-09-29 16:40-16:41，改 defconfig + 重编重烧后）

```text
USART1 CR1 = 0x00000000   ← 原 0x2000002d；整个 USART1 不再启用
USART1 ISR = 0x000000c0   ← 原 0x0de310fe；ORE/NE/FE 全为 0，帧错误消失
USART3 CR1 = 0x2000002d   ← 原 0x00000000；MAVLink 起来了
USART3 ISR = 0x08e000d0   ← 低 4 位 = 0（无 PE/FE/NE/ORE）
NVIC ISER1 = 0x1f208088   ← 原 0x1f008028；IRQ37(USART1) 已摘
PC 采样 ×3  = 0x0802c390 / 0x0802c390 / 0x080239d4（会变，不再卡在 ISR）
/dev/ttyUSB0 @57600：6s / 608 B，帧头 fd，含 HEARTBEAT(msgid 0x00)
                     复测 ≈107 B/s，5s 内 6 个 HEARTBEAT（≈1.2 Hz）
```

**结论**：根因链已被切断，QGC 具备连接条件（P4 全过）。剩 P5 由用户开 QGC 实测。

## 新增认知（防下次踩）

4. PX4 的 cmake 把 `nuttx-config/<配置>/defconfig` 注册为 `CMAKE_CONFIGURE_DEPENDS`
   （`platforms/nuttx/cmake/init.cmake` L56-57），make 会自动 reconfigure 并把新
   defconfig 经 `olddefconfig` 膨胀回 build 树的 `.config`（同文件 L69/L75/L84）。
   → **只改 defconfig 就够，无需手删 .config、无需 distclean**。
5. 验证「`/dev/ttySx` 编号没位移」的方法：比对 `.config` 里 8 个 UART 的使能行
   （本次 L419-426 与改动前一致）→ 注册顺序不变 → ttyS2 仍是 USART3。

