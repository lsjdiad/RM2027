#!/bin/bash
# 在已由 PX4 初始化好的 SPI1 上，用调试器手工发一次 ICM-42688-P 的 WHOAMI 读事务。
# 事务顺序完全复刻 PX4 驱动 probe(): 先写 REG_BANK_SEL(0x76)=0，再读 WHO_AM_I(0x75)。
# 只动 SPI1 的 CR1/CR2/CFG1 + GPIOB 的 CS(PB4)，结束后恢复原值。
CS_LOW=0x00100000     # GPIOB_BSRR bit20 -> reset PB4 (CS low)
CS_HIGH=0x00000010    # GPIOB_BSRR bit4  -> set   PB4 (CS high)
CR1_IDLE=0x00001201   # SPE(0) | SSI(12) | CSTART(9)
set -e
pkill -x openocd 2>/dev/null || true
sleep 1
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "echo {==== BEFORE: SPI1 CR1 CR2 CFG1 CFG2 SR} " -c "mdw 0x40013000 4" -c "mdw 0x40013014" \
 -c "echo {==== BEFORE: GPIOB ODR = }" -c "mdw 0x58020414" \
 -c "echo {==== TEST A @24MHz (MBR=1, f_ker=96MHz) ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "echo {A1 CSTART+TX 0x76(banksel reg)}" -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0x76" \
 -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "echo {A2 CSTART+TX 0x00(banksel val)}" -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0x00" \
 -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "echo {A3 CSTART+TX 0xF5=read 0x75} " -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0xF5" \
 -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "echo {A4 CSTART+TX 0x00 dummy -> RX should be WHOAMI 0x47}" -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0x00" \
 -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x58020418 $CS_HIGH" -c "mdw 0x40013014" \
 -c "echo {==== TEST B @0.75MHz (MBR=6) ====}" \
 -c "mww 0x40013000 0x00001000" -c "mww 0x40013008 0x60070007" -c "mww 0x40013000 0x00001001" \
 -c "mdw 0x40013008" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "echo {B1 TX 0x76} " -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0x76" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "echo {B2 TX 0x00} " -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0x00" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "echo {B3 TX 0xF5} " -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0xF5" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "echo {B4 TX 0x00 -> RX should be 0x47}" -c "mww 0x40013000 $CR1_IDLE" -c "mww 0x40013020 0x00" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {==== RESTORE ====}" \
 -c "mww 0x40013000 0x00001000" -c "mww 0x40013008 0x10070007" -c "mww 0x40013000 0x00001001" \
 -c "mdw 0x40013000 4" -c "mdw 0x58020414" \
 -c "resume" -c "shutdown"
