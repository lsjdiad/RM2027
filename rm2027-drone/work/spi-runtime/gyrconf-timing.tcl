# gyrconf-timing.tcl
# 目的：复现驱动的 GYR_CONF 写时序，定位是哪一步把写入吃掉。
#
# 已知：
#   - 直接写 0x42=0xCC 且前后各留几十 ms ⇒ 成功（gyrconf-test.tcl 已证）
#   - 驱动的顺序是：PWR_CTRL=0 → 1ms → 写 GYR_CONF=0xCC → 【不延时】→ PWR_CTRL=0x0E → 10ms
#   - 驱动实测 0x42 回读恒为缺省 0xA9
#
# 用法：openocd -f gyrconf-timing.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 500
init
halt

echo "### GYRCONF TIMING BEGIN ###"

proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n<300} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc seq {bytes} {
    mww 0x58020418 0x00100000
    dr
    set o {}
    foreach b $bytes { lappend o [xf $b] }
    mww 0x58020418 0x00000010
    return $o
}
proc rd {reg} { set o [seq [list [expr {$reg|0x80}] 0x00]]; return [lindex $o 1] }
proc wr {reg val} { seq [list $reg $val] }
proc rd42 {} { return [rd 0x42] }

echo [format "0) 初始: 7D=%02X 40=%02X 41=%02X 42=%02X 43=%02X" [rd 0x7D] [rd 0x40] [rd 0x41] [rd 0x42] [rd 0x43]]

# ---- 复现驱动时序：PWR_CTRL=0 → 1ms → 写0x42 → 【0ms】→ PWR_CTRL=0x0E → 10ms ----
wr 0x7D 0x00
after 1
echo [format "1) PWR_CTRL=0 后读: 7D=%02X 42=%02X  (驱动此时会 RegisterRead 拿 orig)" [rd 0x7D] [rd 0x42]]
wr 0x42 0xCC
echo [format "2) 写完 0x42=CC（关断中，立即读）: 42=%02X" [rd42]]
wr 0x7D 0x0E
after 10
echo [format "3) PWR_CTRL=0x0E +10ms: 7D=%02X 42=%02X   <<< 驱动就是停在这里读到 A9" [rd 0x7D] [rd 0x42]]

# ---- 变体 A：写完 GYR_CONF 后加 1ms ----
wr 0x7D 0x00
after 1
wr 0x42 0xCC
after 1
wr 0x7D 0x0E
after 10
echo [format "A) 加 1ms:  42=%02X" [rd42]]

# ---- 变体 B：写完 GYR_CONF 后加 5ms ----
wr 0x7D 0x00
after 1
wr 0x42 0xCC
after 5
wr 0x7D 0x0E
after 10
echo [format "B) 加 5ms:  42=%02X" [rd42]]

# ---- 变体 C：PWR_CTRL=0 后等 20ms（不急着写）----
wr 0x7D 0x00
after 20
wr 0x42 0xCC
after 10
wr 0x7D 0x0E
after 20
echo [format "C) 20ms+10ms: 42=%02X" [rd42]]

# ---- 变体 D：先打开 PWR_CTRL 再写 GYR_CONF（反手册顺序）----
wr 0x7D 0x0E
after 10
wr 0x42 0xCC
after 10
echo [format "D) 先开再写: 42=%02X" [rd42]]

echo "### GYRCONF TIMING END ###"
resume
shutdown
