# 加速度计自测：手册 §5.43 流程 + 电气特性表 AVst1/2/3 规格
# 前置（当前芯片已是此配置，手册步骤 2/3 要求）：ACC_RANGE=0x03(±16g)、ACC_CONF=0xAC、
#   PWR_CTRL=0x0E(ACC_EN=1)
# SELF_TEST(0x6D): B3=SELF_TEST_AMP, B2=SELF_TEST_SIGN, B0=SELF_TEST_EN
#   高振幅: AMP=1 → 0x08 ; 负方向: 0x08|0x01 = 0x09 ; 正方向: 0x08|0x04|0x01 = 0x0D
init
halt
echo "### SELFTEST BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
# 读 12 字节数据并输出（一次 CS 窗口突发）
proc datarow {} { set v [seq [list 0x8C 0 0 0 0 0 0 0 0 0 0 0 0]]; set s ""; foreach x [lrange $v 1 12] { append s [format "%02X" $x] }; return $s }

echo "前置检查: ACC_CONF(0x40)=[format %02X [rd 0x40]] ACC_RANGE(0x41)=[format %02X [rd 0x41]] PWR_CTRL(0x7D)=[format %02X [rd 0x7D]] SELF_TEST(0x6D)=[format %02X [rd 0x6D]]"
# 清掉可能残留的自测
wr 0x6D 0x00
after 60
echo "-- 基线（自测关闭）--"
for {set i 0} {$i<6} {incr i} { echo "B [datarow]" }
# 负方向激励
wr 0x6D 0x09
after 60
echo "-- 负方向 (SIGN=0) --"
for {set i 0} {$i<10} {incr i} { echo "N [datarow]" }
# 正方向激励
wr 0x6D 0x0D
after 60
echo "-- 正方向 (SIGN=1) --"
for {set i 0} {$i<10} {incr i} { echo "P [datarow]" }
# 恢复
wr 0x6D 0x00
echo "恢复后 SELF_TEST(0x6D)=[format %02X [rd 0x6D]]"
echo "### SELFTEST END ###"
resume
shutdown
