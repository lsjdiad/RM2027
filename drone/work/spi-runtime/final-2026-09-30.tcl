source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### FINAL BEGIN ###"
w32 0x40013018 0x00001FFF
dr
echo "WHO_AM_I(0x01)=[format %02X [rd1 0x01]]   （板上驱动是否把芯片配起来了）"
echo "关键配置: [readcfg]"
echo "12 字节突发(0x0C~0x17) = [burst 0x8C 12]   （PX4 走的就是这条路）"
show "静止基线 20 样本" [sample 20]
echo "### FINAL END ###"
resume
shutdown
