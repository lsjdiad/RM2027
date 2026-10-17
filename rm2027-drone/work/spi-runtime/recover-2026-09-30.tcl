source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### RECOVER BEGIN ###"
w32 0x40013018 0x00001FFF
dr
echo "前: WHO_AM_I=[format %02X [rd1 0x01]] 0x40=[format %02X [rd1 0x40]] 0x7D=[format %02X [rd1 0x7D]]"
echo "-- 手册 §5.42 SOFT_RST(0x4A)=0xA5 --"
wr 0x4A 0xA5
after 40
echo "后: WHO_AM_I=[format %02X [rd1 0x01]] 0x40=[format %02X [rd1 0x40]] 0x7D=[format %02X [rd1 0x7D]] 0x08=[format %02X [rd1 0x08]]"
echo "### RECOVER END ###"
resume
shutdown
