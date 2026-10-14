source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "=== RCC ==="
mdw 0x58024450 1
mdw 0x580244f0 1
echo "=== SPI1 ==="
mdw 0x40013000 5
echo "=== GPIOA ==="
mdw 0x58020000 1
mdw 0x58020020 1
echo "=== GPIOB ==="
mdw 0x58020400 1
mdw 0x58020414 1
mdw 0x58020420 1
echo "=== GPIOD ==="
mdw 0x58020c00 1
mdw 0x58020c20 1
echo "=== vars ==="
mdw 0x2400bb40 1
mdw 0x0818dfb0 4
resume
shutdown
