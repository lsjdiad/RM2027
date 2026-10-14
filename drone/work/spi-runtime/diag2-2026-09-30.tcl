source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### DIAG2 BEGIN ###"
proc r32 {addr} { mem2array v 32 $addr 1; return [format "0x%08X" $v(0)] }
echo "--- RCC APB2ENR 0x58024450 (结论.md 里是 0x00001031, SPI1EN=bit12) ---"
echo "    0x58024450 = [r32 0x58024450]"
echo "--- RCC AHB4ENR 0x580244e0 (GPIOBEN=bit1) ---"
echo "    0x580244e0 = [r32 0x580244e0]"
echo "--- SPI1 (base 0x40013000) ---"
echo "    CR1  (0x00) = [r32 0x40013000]"
echo "    CR2  (0x04) = [r32 0x40013004]"
echo "    CFG1 (0x08) = [r32 0x40013008]"
echo "    CFG2 (0x0C) = [r32 0x4001300C]"
echo "    IER  (0x10) = [r32 0x40013010]"
echo "    SR   (0x14) = [r32 0x40013014]"
echo "--- GPIOB (base 0x58020400) ---"
echo "    MODER(0x00) = [r32 0x58020400]"
echo "    ODR  (0x14) = [r32 0x58020414]"
echo "    AFRL (0x20) = [r32 0x58020420]"
echo "### DIAG2 END ###"
resume
shutdown
