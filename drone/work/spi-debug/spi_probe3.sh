#!/bin/bash
# v3: 严格复刻 NuttX 驱动的字节级访问（spi_putreg8/spi_getreg8 + RXP/TXP 轮询 + 每笔事务独立 CS 窗口）
CS_LOW=0x00100000
CS_HIGH=0x00000010
CSTART=0x00001201
TX=0x40013020
RX=0x40013030
SR=0x40013014
pkill -x openocd 2>/dev/null || true
sleep 1
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "echo {==== 清空 RX FIFO ====}" -c "mdb 0x40013030" -c "mdb 0x40013030" -c "mdb 0x40013030" -c "mdb 0x40013030" -c "mdw 0x40013014" \
 -c "echo {==== T1 WRITE REG_BANK_SEL(0x76)=0 ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x76" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" -c "mdw $SR" \
 -c "echo {==== T2 READ WHO_AM_I(0x75) : 第2字节应为 0x47 ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" -c "mdw $SR" \
 -c "echo {==== T3 READ reg0x00 : 交叉验证 ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x80" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" -c "mdw $SR" \
 -c "echo {==== T4 再读一次 0x75（确认可重复） ====}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {==== 还原 ====}" -c "mww 0x40013000 0x00001001" -c "mdw 0x58020414" -c "mdw 0x40013000 1" \
 -c "resume" -c "shutdown"
