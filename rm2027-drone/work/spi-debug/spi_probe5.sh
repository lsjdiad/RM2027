#!/bin/bash
CS_LOW=0x00100000
CS_HIGH=0x00000010
CSTART=0x00001201
TX=0x40013020
RX=0x40013030
SR=0x40013014
pkill -x opencd 2>/dev/null || true; pkill -x openocd 2>/dev/null || true
sleep 1
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "echo {== T1 write REG_BANK_SEL(0x76)=0x01 (切到 bank1) ==}" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x76" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x01" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {== T2 read 0x76 (0xF6) -> 若写通路正常应回 0x01 ==}" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF6" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {== T3 write 0x76=0x00 (回 bank0) ==}" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x76" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {== T4 read 0x76 -> 期望 0x00 ==}" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF6" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {== T5 read WHO_AM_I 0x75 -> 期望 0x47 ==}" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {== 降速到 0.75MHz (MBR=6) 再读 WHO_AM_I / 0x76 ==}" \
 -c "mww 0x40013000 0x00001000" -c "mww 0x40013008 0x60070007" -c "mww 0x40013000 0x00001001" -c "mdw 0x40013008" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "mww 0x58020418 $CS_LOW" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF6" -c "mdb $RX" -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {== 还原 CFG1 / CS ==}" -c "mww 0x40013000 0x00001000" -c "mww 0x40013008 0x10070007" -c "mww 0x40013000 0x00001001" -c "mdw 0x58020414" \
 -c "resume" -c "shutdown"
