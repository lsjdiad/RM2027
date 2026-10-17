# chipstate-safe.tcl —— 只读芯片当前寄存器
#
# ⚠️⚠️ CR1 取值（2026-09-30 深夜实测 A/B，见 `cri-ab.tcl`）：
#   **手工用 GPIO 拉 CS（本脚本的做法）⇒ CR1 必须是 `0x00001201`（含 bit9 SSM=1）**
#   · `0x1201` → WHO_AM_I=0x6A / 0x7D=0x0E / 0x0B=0x07 / 0x40=0x8C / 0x42=0xCC   ✅ 正确
#   · `0x1001` → 全 0x00                                                          ❌ 读不到器件
#   原因：`0x1001` 是**固件自己**的配置（NSS 交给 SPI 外设/PE4 复用），SSM=0；
#         手工拉 CS 时若 SSM=0，SSI 被忽略、NSS 由外设驱动，与手工 GPIO 打架 ⇒ 帧错位 ⇒ 全 0x00。
#   ⚠️ `结论文档-器件身份与锁死真相.md` 里写的"CR1 应为 0x1001"是**针对固件侧**的说法，
#      拿它去做手工 CS 读**会读出全 0**，从而**误判成"芯片锁死"** —— 这个坑本身就是一个坑。
#
# 其余安全规矩（同 §3）：
#   · 会话开头先清 IFCR（含 MODF/SUSP），否则读到的是陈旧 RXDR
#   · xf 轮询上限 300（老脚本 20000：SPI 不响应时每字节烧 10 秒）
#   · 绝对不写 CR1=0
#
# 用法： openocd -f chipstate-safe.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### CHIPSTATE-SAFE BEGIN ###"

proc r32 {a} { mem2array v 32 $a 1; return $v(0) }
proc w32 {a v} { mww $a $v }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    w32 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n<300} { if {([srr]&1)!=0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }
proc rd1 {reg} { cslo; dr; xf [expr {$reg | 0x80}]; set b [xf 0x00]; cshi; return $b }

# --- 安全前奏：清 IFCR ---
w32 0x40013018 0x00001FFF
after 2

echo [format "固件侧 SPI1 CR1=%08X SR=%08X" [r32 0x40013000] [r32 0x40013014]]

set who [rd1 0x01]
echo [format "WHO_AM_I(0x01)=%02X  %s" $who [expr {$who == 0x6A ? "(与手册缺省一致)" : "(不是 0x6A!)"}]]
echo [format "0x0B DATA_STAT=%02X  0x40 ACC_CONF=%02X  0x41 ACC_RANGE=%02X" [rd1 0x0B] [rd1 0x40] [rd1 0x41]]
echo [format "0x42 GYR_CONF =%02X  0x43 GYR_RANGE=%02X 0x7D PWR_CTRL=%02X" [rd1 0x42] [rd1 0x43] [rd1 0x7D]]

# --- 收尾：CR1 交还固件侧配置 + CS 拉高 ---
w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### CHIPSTATE-SAFE END ###"
resume
shutdown
