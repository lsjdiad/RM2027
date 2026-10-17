# 只读复核：确认本板器件 SPI 读【没有 dummy 字节】
init
halt
echo "### VERIFY-DUMMY BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc xfer {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc drain {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc seq {bytes} {
    mww 0x58020418 0x00100000
    drain
    set out {}
    foreach b $bytes { lappend out [xfer $b] }
    mww 0x58020418 0x00000010
    return $out
}
# PX4 的 BMI270 驱动 = 3 字节传输，取 cmd-2
echo "PX4_RegisterRead(0x00) => [lindex [seq [list 0x80 0x00 0x00]] 2]   (期望 0x24；补丁接受 0x00)"
echo "PX4_RegisterRead(0x40) => [lindex [seq [list 0xC0 0x00 0x00]] 2]   (ACC_CONF 应为 0xA8)"
echo "PX4_RegisterRead(0x42) => [lindex [seq [list 0xC2 0x00 0x00]] 2]   (GYR_CONF 应为 0xA9)"
echo "--- 同一批寄存器，2 字节传输取 cmd-1 ---"
echo "2B_Read(0x00) => [lindex [seq [list 0x80 0x00]] 1]"
echo "2B_Read(0x01) => [lindex [seq [list 0x81 0x00]] 1]"
echo "2B_Read(0x40) => [lindex [seq [list 0xC0 0x00]] 1]"
echo "2B_Read(0x42) => [lindex [seq [list 0xC2 0x00]] 1]"
echo "2B_Read(0x44) => [lindex [seq [list 0xC4 0x00]] 1]"
echo "2B_Read(0x45) => [lindex [seq [list 0xC5 0x00]] 1]"
echo "2B_Read(0x7C) => [lindex [seq [list 0xFC 0x00]] 1]"
echo "2B_Read(0x7D) => [lindex [seq [list 0xFD 0x00]] 1]"
echo "--- 单窗口 5 字节突发 0x40 起（看真实排列）---"
echo "burst(0xC0,0,0,0,0) => [seq [list 0xC0 0x00 0x00 0x00 0x00]]"
mww 0x40013000 0x00001001
mww 0x58020418 0x00000010
echo "### VERIFY-DUMMY END ###"
resume
shutdown
