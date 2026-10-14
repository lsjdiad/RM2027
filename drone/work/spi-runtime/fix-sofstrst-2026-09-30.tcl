source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### FIX BEGIN ###"
w32 0x40013018 0x00001FFF
dr
echo "WHO_AM_I=[format %02X [rd1 0x01]]  PWR_CTRL(0x7D)=[format %02X [rd1 0x7D]]  DATA_STAT(0x0B)=[format %02X [rd1 0x0B]]"
echo "-- 诊断：逐寄存器单读 0x0C~0x17（5 组）--"
for {set i 0} {$i < 5} {incr i} {
    set s ""
    for {set r 0x0C} {$r <= 0x17} {incr r} { append s [format "%02X" [rd1 $r]] }
    echo "  single $s"
}
echo "-- 诊断：12 字节突发 0x0C~0x17（3 次）--"
for {set i 0} {$i < 3} {incr i} { echo "  burst  [burst 0x8C 12]" }
echo ""
echo "-- 手册 §5.42 SOFT_RST(0x4A)=0xA5（文档化寄存器）--"
wr 0x4A 0xA5
after 20
echo "复位后 WHO_AM_I=[format %02X [rd1 0x01]]  PWR_CTRL=[format %02X [rd1 0x7D]]  0x40=[format %02X [rd1 0x40]]"
echo "-- 复位后：12 字节突发 3 次 --"
for {set i 0} {$i < 3} {incr i} { echo "  burst  [burst 0x8C 12]" }
echo "-- 复位后：逐寄存器单读 3 组 --"
for {set i 0} {$i < 3} {incr i} {
    set s ""
    for {set r 0x0C} {$r <= 0x17} {incr r} { append s [format "%02X" [rd1 $r]] }
    echo "  single $s"
}
echo "### FIX END ###"
resume
shutdown
