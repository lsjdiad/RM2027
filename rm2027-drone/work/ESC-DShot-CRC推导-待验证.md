# DShot CRC 推导（**待上机验证，暂不改代码**）

> 状态：**仅存档推理，不作为改动依据**（2026-10-02）
> 背景：讨论"F103 发的 DShot 帧 CRC 是否正确"时，从 AM32 解码器推出结论。
>      但当时帧长本身就是错的（15 位 vs 16 位），**CRC 对不对根本无法验证**，
>      所以按"一次只改一件事"的纪律，**先不改 CRC，只修帧长**。

---

## 推导过程（依据 AM32 自己的解码器）

**源码：`AM32/Src/dshot.c` → `computeDshotDMA()`**
```c
uint8_t calcCRC = ((dpulse[0] ^ dpulse[4] ^ dpulse[8]) << 3
                 | (dpulse[1] ^ dpulse[5] ^ dpulse[9]) << 2
                 | (dpulse[2] ^ dpulse[6] ^ dpulse[10]) << 1
                 | (dpulse[3] ^ dpulse[7] ^ dpulse[11]));
uint8_t checkCRC = (dpulse[12] << 3 | dpulse[13] << 2 | dpulse[14] << 1 | dpulse[15]);
int tocheck = (dpulse[0] << 10 | ... | dpulse[10]);     // 11 位油门
```

**`dpulse[0]` 是【最先发出的位】= 帧的 bit15。**
**记 16 位帧为 F（F15 先发），则 `dpulse[i] = F(15-i)`。**

**展开 `calcCRC`（位 3..0）：**
```
C3 = dpulse[0]^dpulse[4]^dpulse[8] = F15^F11^F7
C2 = dpulse[1]^dpulse[5]^dpulse[9] = F14^F10^F6
C1 = dpulse[2]^dpulse[6]^dpulse[10]= F13^F9 ^F5
C0 = dpulse[3]^dpulse[7]^dpulse[11]= F12^F8 ^F4
```

**而 `checkCRC` = F3..F0（帧的最后 4 位）。**

**把 F 写成 `F = (P << 4) | C`，其中 P 是 12 位 packet（= 油门<<1 | 遥测位）：**
```
F15..F4 = P11..P0
⇒ C3 = P11^P7^P3
  C2 = P10^P6^P2
  C1 = P9 ^P5^P1
  C0 = P8 ^P4^P0
⇒ 【C = (P ^ (P>>4) ^ (P>>8)) & 0xF】   ← CRC 的输入是【12 位的 P】
```

## 结论（**待验证**）
**标准 DShot 帧构造应为：**
```c
uint16_t packet = (throttle & 0x7FF) << 1;      // 12 位
if (telem) packet |= 1;
uint16_t crc = (packet ^ (packet >> 4) ^ (packet >> 8)) & 0xF;
uint16_t frame = (packet << 4) | crc;
```

**而"直接对 `(throttle<<5)`（= P<<4）算 CRC"会得到**不同的值**。**

---

## 为什么现在不改

1. **帧长本身是错的**（15 位）⇒ CRC 正确与否**不可观测**
2. **一次只改一个变量**：先修帧长（关预装载），看电调是否接受
3. **验证路径**：
   - 关预装载后，若 `dshot=1` 且 `input` 跟着走 ⇒ **CRC 本来就是对的**（我的推导错了）
   - 若帧长对了但电调仍不认 ⇒ **CRC 就是下一个嫌疑**，此时再按上面的公式改，并用电调行为验证

---

## 参考数据（自测用）
| 油门 | CRC 用 12 位 P | frame |
|---|---|---|
| 0 | 0x0 | 0x0000 |
| 1 | 0x2 | 0x0022 |
| 48 | 0x6 | 0x0606 |
| 200 | 0x8 | 0x1908 |
| 2047 | 0xE | 0xFFEE |
