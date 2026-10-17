# 只读诊断：读取运行中 PX4 的 SPI1 / GPIO / RCC 寄存器状态
# 不写任何寄存器，不做 reset。用完 resume。
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "===== RCC ====="
echo "D2CCIP1R  (SPI123SEL = bits12-14):"
mdw 0x58024450 1
echo "APB2ENR   (SPI1EN = bit12):"
mdw 0x580244f0 1
echo "===== SPI1 @0x40013000 ====="
echo "CR1 CFG1 CFG2 IER SR (5 words):"
mdw 0x40013000 5
echo "===== GPIOA (PA6=MISO) ====="
echo "MODER AFRL:"
mdw 0x58020000 1
mdw 0x58020020 1
echo "===== GPIOB (PB3=SCK PB4=CS) ====="
echo "MODER ODR AFRL:"
mdw 0x58020400 1
mdw 0x58020414 1
mdw 0x58020420 1
echo "===== GPIOD (PD6=DRDY PD7=MOSI) ====="
echo "MODER AFRL:"
mdw 0x58020c00 1
mdw 0x58020c20 1
echo "===== PX4 变量 ====="
echo "_spi_bus1 (应非0):"
mdw 0x2400bb40 1
echo "px4_spi_buses[0] 前 16 字节 (应 14 01 04 00 36 01 00 00 26 00 00 10 26 00 00 00):"
mdw 0x0818dfb0 4
echo "===== 结束 ====="
resume
shutdown
