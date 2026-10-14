#!/bin/bash
# 烧写测试固件到 app 槽 0x08001000 并运行
#   ./flash.sh              烧 test_a_low_1khz.bin （PB15 约 1kHz 翻转，示波器用）
#   ./flash.sh static       烧 test_a_low_static.bin（PB15 常高，万用表用）
set -e
cd "$(dirname "$0")"

if [ "${1:-1khz}" = "static" ]; then
  BIN=test_a_low_static.bin
else
  BIN=test_a_low_1khz.bin
fi
[ -f "$BIN" ] || { echo "❌ 找不到 $BIN，先跑 ./build.sh"; exit 1; }

sudo openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "adapter speed 500" -c "init" -c "reset halt" \
  -c "flash write_image erase $PWD/$BIN 0x08001000" \
  -c "verify_image $PWD/$BIN 0x08001000" \
  -c "reset halt" \
  -c "mem2array v 32 0x08001000 2" \
  -c "reg msp \$v(0)" -c "reg pc \$v(1)" \
  -c "resume" -c "shutdown"
echo "✅ 已烧写 $BIN 并启动（PB15=A_LIN 按设定输出，PB0/PA7 及其余门极全低）"
