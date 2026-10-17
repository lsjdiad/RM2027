#!/bin/bash
pkill -x openocd 2>/dev/null || true
sleep 1
args=(-f interface/stlink.cfg -f target/stm32h7x.cfg -c init -c halt)
CSL="mww 0x58020418 0x00100000"
CSH="mww 0x58020418 0x00000010"
ST="mww 0x40013000 0x00001201"
R() { args+=(-c "$CSL" -c "$ST" -c "mwb 0x40013020 $1" -c "mdb 0x40013030" -c "$ST" -c "mwb 0x40013020 0x00" -c "mdb 0x40013030" -c "$CSH"); }
W() { args+=(-c "$CSL" -c "$ST" -c "mwb 0x40013020 $1" -c "mdb 0x40013030" -c "$ST" -c "mwb 0x40013020 $2" -c "mdb 0x40013030" -c "$CSH"); }
args+=(-c "echo {== 基线 r75 r0b r1d r11 ==}" ); R 0xF5; R 0x8B; R 0x9D; R 0x91
args+=(-c "echo {== 软复位 写0x11=0x01 ==}"); W 0x11 0x01
args+=(-c "sleep 300")
args+=(-c "echo {== 复位后 r75 r0b r1d r11 ==}"); R 0xF5; R 0x8B; R 0x9D; R 0x91
args+=(-c "echo {== 0x76 写0xA5读回(genuine 3bit 应回 05) ==}"); W 0x76 0xA5; R 0xF6
args+=(-c "echo {== 0x76 写0x5A读回(应回 02) ==}"); W 0x76 0x5A; R 0xF6
args+=(-c "echo {== 0x76=0 后 r75 ==}"); W 0x76 0x00; R 0xF5
args+=(-c "mww 0x40013000 0x00001001" -c resume -c shutdown)
exec openocd "${args[@]}"
