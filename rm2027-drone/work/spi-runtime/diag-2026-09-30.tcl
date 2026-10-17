source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### DIAG BEGIN ###"
echo "--- RCC (对照 结论.md: APB2ENR 应为 0x00001031, SPI1EN=1) ---"
mdw 0x58024450 1
mdw 0x580244f0 1
echo "--- SPI1 CR1/CR2/CFG1/CFG2/IER (0x40013000..0x10) ---"
mdw 0x40013000 5
echo "--- SPI1 SR (0x40013014) ---"
mdw 0x40013014 1
echo "--- GPIOB MODER / ODR / AFRL（PB3=SCK/PB4=CS）---"
mdw 0x58020400 1
mdw 0x58020414 1
mdw 0x58020420 1
echo "--- RCC AHB4ENR（GPIOBEN 应为 1）0x580244e0 ---"
mdw 0x580244e0 1
echo "### DIAG END ###"
resume
shutdown
