# gyrconf-test.tcl
# 唯一目的：查清 0x42 GYR_CONF 为什么写不进 0xCC（回读恒为缺省 0xA9）
#
# 背景：hxy42688p 驱动已按手册 §5.39 备注实现「先关 ACC+GYR → 写 GYR_CONF → 再打开」，
#       但实测 0x42 回读恒为 0xA9（缺省），而 0x40/0x41/0x7D 都能写进去。
#       本脚本用 ST-Link + 手工 SPI1 逐种顺序试，找出能写进去的那一种。
#
# ⚠️ 会用 PWR_CTRL 关掉传感器；脚本结尾会恢复 PWR_CTRL=0x0E。
#    若中途失败，断电重上电即可恢复（PX4 下次启动会重新配置）。
#
# 用法：openocd -f gyrconf-test.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 500
init
halt

echo "### GYRCONF TEST BEGIN ###"

proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }

# 单次字节交换；轮询上限 300（教训：长轮询会让脚本挂死）
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
proc wr {reg val} { seq [list $reg $val]; after 2 }

proc dump {tag} {
    echo [format "%s  7D=%02X 40=%02X 41=%02X 42=%02X 43=%02X 0B=%02X" \
        $tag [rd 0x7D] [rd 0x40] [rd 0x41] [rd 0x42] [rd 0x43] [rd 0x0B]]
}

dump "BEFORE          "

# ---- A 方案：手册 §5.39 的顺序（关 → 写 → 开），驱动当前就是这么做的 ----
wr 0x7D 0x00
after 20
dump "A1 PWR_CTRL=0   "
wr 0x42 0xCC
after 10
dump "A2 wrote42=CC(off)"
wr 0x7D 0x0E
after 20
dump "A3 PWR_CTRL=0x0E"

# ---- B 方案：不动 PWR_CTRL，直接写 ----
wr 0x42 0xCC
after 10
dump "B  direct 42=CC "

# ---- C 方案：只改 ODR，不开 GYR_NOISE_PERF（0xAC = PERF1/NOISE0/BWP10/ODR1100=1600Hz）----
wr 0x42 0xAC
after 10
dump "C  42=AC (no NOISE)"

# ---- D 方案：写回缺省值，验证写入通路本身是否通 ----
wr 0x42 0xA9
after 10
dump "D  42=A9 (default) "

# ---- E 方案：写一个明显不同的值（只改 ODR 到 100Hz：0x88 = PERF1/BWP00? 这里用 0xA8+? ）----
#     0xA2 = 1010 0010 → PERF=1, NOISE=0, BWP=10, ODR=0010(保留) ⇒ 会被器件拒绝
#     改用 0xAA = 1010 1010 → PERF=1, NOISE=0, BWP=10, ODR=1010(400Hz) —— 合法且与缺省不同
wr 0x42 0xAA
after 10
dump "E  42=AA (400Hz)  "

# ---- 收尾：恢复一个合法配置（1600Hz 高性能，若写不进就落回缺省）----
wr 0x42 0xCC
after 5
wr 0x7D 0x0E
after 20
dump "FINAL           "

echo "### GYRCONF TEST END ###"
resume
shutdown
