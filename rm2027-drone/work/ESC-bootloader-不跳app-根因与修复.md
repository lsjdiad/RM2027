# ★ 电调 bootloader 不跳 app —— 根因与修复（已解决）

> 解决日期：2026-10-02　　状态：**已验证修复**
> 影响：这是"电调为什么每次上电都不自动运行"的**唯一原因**，曾长时间阻塞调试。

---

## 一、现象

```
每次上电 / 复位后：pc 停在 0x08000104（bootloader 区内）
⇒ app 从不执行 ⇒ 不响应 DShot、门极静止、三相无输出
⇒ 只能靠 SWD 手工装 SP/PC 强制启动，一断电就白干
```

---

## 二、根因（反汇编 bootloader 得到）

**bootloader 在跳 app 之前，检查参数区第 1 个字节：**

```asm
800046c:  ldr  r3, [pc, #80]   ; r3 = 0x0801F800  ← 参数区(EEPROM)首地址
800046e:  ldrb r0, [r3, #0]    ; r0 = *(0x0801F800)   ← 读第 1 个字节
8000470:  cmp  r0, #1
8000472:  beq.n 0x800047c      ; ★【必须 == 1 才继续】
8000474:  movs r2, #0          ; 否则：
          ldr  r3, =0x20000026
          strh r2, [r3, #0]
          bx   lr              ; ← 【返回 ⇒ 永远待在 bootloader】

800047c:  ; 校验 1：app 的栈指针合法吗
          ldr  r2, [0x08001000]        ; SP
          adds r2, r2, #0xE0000000     ; 巧妙的范围检查（加法回绕）
          cmp  r2, #0x10000 ; bhi → 不跳
          ; 校验 2：app 的复位向量合法吗
          ldr  r2, [0x08001004]
          adds r2, r2, #0xF7FFF000
          cmp  r2, #0x40000 ; bhi → 不跳
          ↓ 两项都过
80004b8:  msr  MSP, r2 ; bx r1   ; ★ 跳 app
```

**对应 AM32 的参数区结构（`Inc/eeprom.h`）：**
```c
typedef union EEprom_u {
  struct {
    uint8_t reserved_0;      // 字节0  ← ★ bootloader 用这个当"app 有效"标志
    uint8_t eeprom_version;  // 字节1
    ...
```

**⇒ 这个字节**不是 AM32 的业务字段**（叫 `reserved_0`，AM32 自己不写它）——
它是 **bootloader 与 app 之间的握手标志**。

---

## 三、为什么它是 0xFF

```
实测 0x0801F800（CPU 停住后）：
  offset 0 = 0xFF    ← 标志没写
  offset 1 = 0x04    = eeprom_version
  offset 3 = 0x02 ┐
  offset 4 = 0x15 ┘  = version 2.21（我们的版本）
  其余 99% 为 0xFF（未初始化）

⇒ 说明 AM32 写过版本字段，但【标志从来没被写过】
```

**因果链：**
```
① app 是用【SWD 直接烧到 0x08001000】的 —— 绕过了 bootloader
② ⇒ bootloader 没有机会执行"烧写成功 ⇒ 置标志"那一步
③ ⇒ 每次上电检查 *(0x0801F800) == 1 失败 ⇒ 拒绝跳 app
④ ⇒ 你看到的"卡在 bootloader 等一个永远不来的信号"
```

---

## 四、修复（已验证）

**把 `0x0801F800` 的第 1 个字节写成 `0x01`。**

```bash
# ① 读出整个 2 KB 参数页
openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "init; halt" -c "dump_image /tmp/eeprom.bin 0x0801F800 0x800" -c "shutdown"

# ② 把字节 0 改成 0x01（其余 2047 字节原样，用 python）
python3 -c "
d=bytearray(open('/tmp/eeprom.bin','rb').read()); d[0]=0x01
open('/tmp/eeprom_fixed.bin','wb').write(bytes(d))"

# ③ 写回（含擦除）
openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "init; halt" -c "flash write_image erase /tmp/eeprom_fixed.bin 0x0801F800" \
  -c "reset run" -c "shutdown"
```

**验证结果：**
```
0x0801F800 = 02ff0401   → 字节0 = 0x01 ✓
纯 reset run（不手工干预）:
  第 1 次: pc = 0x08006c50   ← app ✓
  第 2 次: pc = 0x08001324   ← app ✓
```

**安全性**：该字节是 `reserved_0`（AM32 不用），且参数区 99% 未初始化；
另有整片 64 KB 备份 `work/esc-flash-backup-2026-10-01.bin`。

---

## 五、★ 操作纪律（重要，别再踩）

> **每次用 SWD/openocd 烧 app 到 `0x08001000` 之后，都要重新写一次这个标志。**

**否则下一次上电又会卡在 bootloader。** 写成脚本：

```bash
# 烧 app 后顺手补标志（把 flag 补上）
openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "init; halt" \
  -c "flash write_image erase /tmp/eeprom_fixed.bin 0x0801F800" \
  -c "reset run" -c "shutdown"
```

**（`work/esc-run.sh` 应加上这一步。）**

---

## 六、副产品：顺手验证了 AM32 的版本握手

```
参数区 offset 3/4 = (2, 21)  ← 与编译出的固件版本 2.21 一致
对应 Src/main.c:1812 的检查：
  if (VERSION_MAJOR != eepromBuffer.version.major || ... ||
      EEPROM_VERSION > eepromBuffer.eeprom_version) {
      // 版本不符 ⇒ 写入默认值
  }
```
**⇒ 换固件版本后参数区会自动重置，不用担心残留旧配置。**

---

## 七、★ 从这次踩坑提炼出的一条纪律

> **凡是用「flash 里一个标志位」决定启动行为的固件，必须交代三件事：**
> **① 谁写它 ② 何时写 ③ 写失败 / 掉电了怎么办。**

**我们这次踩坑，恰恰漏的是第 ③ 件** —— AM32 的 bootloader 文档从没提"它要 `EEPROM[0] == 1` 才跳 app"，
而用 SWD 直烧 app 时谁也写不到那个字节 ⇒ **表现为"电调坏了"，实际是协议层。**

### 独立旁证：PX4 的 H7 bootloader 里有同一个失败模式

`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`（5574 字节）的头注释原文：

> *"A torn write to a flash row (power lost mid program/erase) can leave it with inconsistent ECC.
> On H7 a CPU read of such a row raises an uncorrectable (double-bit) ECC error → bus fault,
> so **the application hard-faults on every boot before it can print anything, and only a mass erase
> recovers it — reflashing does not**, because neither the app nor the bootloader image touches the
> parameter sector."*

**⇒ 对照表：**

| | PX4 H7 bootloader | 我们的 G071 电调 |
|---|---|---|
| 症状 | 每次开机 hardfault，连日志都打不出 | 每次上电停在 bootloader，app 不跑 |
| 根因 | flash 某行半写 ⇒ ECC 错 | **flash 第 0 字节（app 有效标志）= 0xFF** |
| 为何难查 | 无法输出 | 现象像"电调坏了"，其实是协议层 |
| 救法 | DMA 扫 + 擦坏扇区（`check_ecc_errors()`，调用点 `stm32_common/main.c:689`） | **写回该字节 = 1** |
| **共同点** | **一个 flash 字节的状态决定板子能不能用，而失败模式是静默的** | 同左 |

**⇒ 连"重刷固件救不了"这句都同构**：PX4 那边是"app/bootloader 都不碰参数扇区"，
我们这边是"重刷 app 没用，因为问题在 bootloader 读的那个标志位"。

**⇒ 所以这条纪律不是我们运气差，而是这类设计的**固有隐患**：
只要有一个"静默的 flash 标志位"参与启动决策，就必须显式交代它的写入方与恢复路径。**
