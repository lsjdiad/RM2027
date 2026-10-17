#!/bin/bash
# v2: 每笔事务都完整拉低/拉高 CS（v1 忘了在事务之间抬高 CS，导致芯片把它当成一笔 4 字节 burst 写）
CS_LOW=0x00100000
CS_HIGH=0x00000010
CSTART=0x00001201
pkill -x openocd 2>/dev/null || true
sleep 1
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "echo {==== BEFORE CR1 CFG1 CFG2 SR / GPIOB ODR ====}" -c "mdw 0x40013000 1" -c "mdw 0x40013008 2" -c "mdw 0x40013014" -c "mdw 0x58020414" \
 -c "echo {==== T1: WRITE REG_BANK_SEL(0x76)=0  (CS 完整一笔) ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mww 0x40013020 0x76" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x40013000 $CSTART" -c "mww 0x40013020 0x00" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {==== T2: READ WHO_AM_I(0x75) -> 期望第 2 字节 0x47 ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mww 0x40013020 0xF5" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x40013000 $CSTART" -c "mww 0x40013020 0x00" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {==== T3: READ 0x00 (DEVICE_CONFIG) 交叉验证 ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mww 0x40013020 0x80" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x40013000 $CSTART" -c "mww 0x40013020 0x00" -c "mdw 0x40013014" -c "mdw 0x40013030" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {==== 恢复: CS 高 / CR1=SPE|SSI ====}" -c "mww 0x40013000 0x00001001" -c "mdw 0x58020414" -c "mdw 0x40013000 1" \
 -c "resume" -c "shutdown"
