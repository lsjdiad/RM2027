source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### STATUS3 BEGIN ###"
echo [format "SPI1 CR1=%08X CFG1=%08X CFG2=%08X SR=%08X" [r32 0x40013000] [r32 0x40013008] [r32 0x4001300C] [srr]]
# 带重试的 WHO_AM_I 自检：每次先清 IFCR（SUSP/MODF）再读
set ok 0
for {set i 1} {$i <= 5} {incr i} {
    w32 0x40013018 0x00001FFF
    dr
    after 2
    set who [rd1 0x01]
    echo [format "  尝试%d: WHO_AM_I(0x01)=%02X  SR=%08X" $i $who [srr]]
    if {$who == 0x6A} { set ok 1; break }
}
echo "WHO_AM_I 自检: [expr {$ok ? {✓ 通过} : {✗ 失败}}]"
echo "配置: [readcfg]"
echo "TEMP(0x22/0x23) = [format %02X%02X [rd1 0x22] [rd1 0x23]]"
show "BASE20" [sample 20]
echo "### STATUS3 END ###"
resume
shutdown
