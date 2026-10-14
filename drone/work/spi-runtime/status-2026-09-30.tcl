source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### STATUS BEGIN ###"
echo [format "修复脚本后: SPI1 CR1=%08X SR=%08X CFG1=%08X CFG2=%08X" [r32 0x40013000] [srr] [r32 0x40013008] [r32 0x4001300C]]
spi_resync
echo [format "resync 后:  SPI1 CR1=%08X SR=%08X" [r32 0x40013000] [srr]]
echo "WHO_AM_I(0x01)=[format %02X [rd1 0x01]]"
echo "配置: [readcfg]"
show "BASE20" [sample 20]
echo "### STATUS END ###"
resume
shutdown
