source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### REPAIR BEGIN ###"
proc r32 {addr} { mem2array v 32 $addr 1; return $v(0) }
proc w32 {addr val} { mww $addr $val }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    w32 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }
proc rd1 {reg} { cslo; dr; xf [expr {$reg | 0x80}]; set b [xf 0x00]; cshi; return $b }

echo [format "修复前: CR1=%08X SR=%08X CFG1=%08X CFG2=%08X" [r32 0x40013000] [srr] [r32 0x40013008] [r32 0x4001300C]]
# 关键：先清 IFCR（含 MODF bit9 / SUSP bit11），再在 SSI=1 的前提下重新置 SPE
w32 0x40013018 0x00001FFF
w32 0x40013008 0x30070007
w32 0x4001300C 0x87400000
w32 0x40013000 0x00001001
after 5
echo [format "修复后: CR1=%08X SR=%08X" [r32 0x40013000] [srr]]
echo [format "WHO_AM_I(0x01)=%02X  ACC_CONF(0x40)=%02X  ACC_RANGE(0x41)=%02X  GYR_CONF(0x42)=%02X  GYR_RANGE(0x43)=%02X  PWR_CTRL(0x7D)=%02X  DATA_STAT(0x0B)=%02X  0x08=%02X" \
    [rd1 0x01] [rd1 0x40] [rd1 0x41] [rd1 0x42] [rd1 0x43] [rd1 0x7D] [rd1 0x0B] [rd1 0x08]]
echo "### REPAIR END ###"
resume
shutdown
