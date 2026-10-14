#!/bin/bash
pkill -x openocd 2>/dev/null || true
sleep 1
args=(-f interface/stlink.cfg -f target/stm32h7x.cfg -c init -c halt)
CSL="mww 0x58020418 0x00100000"; CSH="mww 0x58020418 0x00000010"; ST="mww 0x40013000 0x00001201"
R() { args+=(-c "$CSL" -c "$ST" -c "mwb 0x40013020 $1" -c "mdb 0x40013030" -c "$ST" -c "mwb 0x40013020 0x00" -c "mdb 0x40013030" -c "$CSH"); }
W() { args+=(-c "$CSL" -c "$ST" -c "mwb 0x40013020 $1" -c "mdb 0x40013030" -c "$ST" -c "mwb 0x40013020 $2" -c "mdb 0x40013030" -c "$CSH"); }
args+=(-c "echo {### r75(WHO_AM_I?) 是否可写 ###}")
args+=(-c "echo {写 0x75=0x5A 后读 0x75:}"); W 0x75 0x5A; R 0xF5
args+=(-c "echo {写 0x75=0x00 后读 0x75:}"); W 0x75 0x00; R 0xF5
args+=(-c "echo {### 现场恢复检查 ###}")
args+=(-c "echo {CFG1 CFG2 CR1:}" -c "mdw 0x40013008 2" -c "mdw 0x40013000 1" -c "mdw 0x40013014")
args+=(-c "echo {GPIOB ODR(bit4=CS 应为 1):} " -c "mdw 0x58020414")
args+=(-c "resume" -c shutdown)
exec openocd "${args[@]}"
