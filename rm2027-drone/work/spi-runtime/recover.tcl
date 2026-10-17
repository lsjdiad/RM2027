init
halt
echo "### RECOVER BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<300} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }

# 先修好 SPI1 状态：清 IFCR(MODF/SUSP)，确认 CR1=0x1001
echo [format "修复前 SPI1 CR1=%08X SR=%08X" [expr {[lindex [seq [list 0x00 0x00]] 1]}] 0]
mww 0x40013018 0xFFFFFFFF   ;# IFCR 全清
mww 0x40013000 0x00001001   ;# CR1 = SPE|SSI
after 5
echo [format "修复后 WHO_AM_I(0x01)=%02X  PWR_CTRL(0x7D)=%02X  DATA_STAT(0x0B)=%02X" [rd 0x01] [rd 0x7D] [rd 0x0B]]

echo "-- 尝试 1: HXY 手册 §5.42 SOFT_RST(0x4A) = 0xA5 --"
wr 0x4A 0xA5
after 100
echo [format "  之后 WHO_AM_I=%02X  PWR_CTRL=%02X  DATA_STAT=%02X  0x40=%02X" [rd 0x01] [rd 0x7D] [rd 0x0B] [rd 0x40]]

echo "-- 尝试 2: BMI270 风格 CMD(0x7E) = 0xB6 (ACC_SOFTRESET) --"
wr 0x7E 0xB6
after 100
echo [format "  之后 WHO_AM_I=%02X  PWR_CTRL=%02X  DATA_STAT=%02X  0x40=%02X" [rd 0x01] [rd 0x7D] [rd 0x0B] [rd 0x40]]

echo "-- 尝试 3: 两个都写，长时间等待 --"
wr 0x4A 0xA5
after 50
wr 0x7E 0xB6
after 500
echo [format "  之后 WHO_AM_I=%02X  PWR_CTRL=%02X  DATA_STAT=%02X  0x40=%02X 0x41=%02X" [rd 0x01] [rd 0x7D] [rd 0x0B] [rd 0x40] [rd 0x41]]
echo "### RECOVER END ###"
resume
shutdown
