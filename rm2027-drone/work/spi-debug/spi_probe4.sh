#!/bin/bash
CS_LOW=0x00100000
CS_HIGH=0x00000010
CSTART=0x00001201
TX=0x40013020
RX=0x40013030
SR=0x40013014
IDRA=0x58020010
pkill -x openocd 2>/dev/null || true
sleep 1
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "echo {#### A: burst read 0x75, dummy=0x00 x6 ####}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdw $SR" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {-- 地址帧后 CS=低、不抬 CS，先看 MISO 电平(IDR bit6) --}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdw $SR" -c "mdb $RX" -c "mdw $IDRA" \
 -c "echo {-- 继续 6 个 dummy=0x00 --}" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" -c "mdw $IDRA" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {#### B: 同样读 0x75，但 dummy=0xFF x6（若数据跟着 MOSI 变，说明是串扰/浮空假象）####}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xF5" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "echo {#### C: 空转（不发地址）同样 dummy=0xFF，测纯浮空/串扰基线 ####}" \
 -c "mww 0x58020418 $CS_LOW" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0xFF" -c "mdb $RX" \
 -c "mww 0x40013000 $CSTART" -c "mwb $TX 0x00" -c "mdb $RX" \
 -c "mww 0x58020418 $CS_HIGH" \
 -c "mww 0x40013000 0x00001001" \
 -c "echo {#### D: PD6(GYRO_INT1) 电平 —— 悬空还是被芯片驱动 ####}" -c "mdw $IDRA" -c "mdw 0x58020C0C" -c "mdw 0x58020C00" \
 -c "resume" -c "shutdown"
