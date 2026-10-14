#!/bin/bash
# 烧写走查固件到 app 槽 0x08001000 并运行（同一套 reset + 装 SP/PC 的手法，见 flash.sh）
#   ./flash_pinwalk.sh                 烧 test_pinwalk.bin（顺序走查）
#   ./flash_pinwalk.sh test_pinwalk_hold2.bin
set -e
cd "$(dirname "$0")"
BIN="${1:-test_pinwalk.bin}"
[ -f "$BIN" ] || { echo "❌ 找不到 $BIN，先跑 ./build_pinwalk.sh"; exit 1; }

sudo openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "adapter speed 500" -c "init" -c "reset halt" \
  -c "flash write_image erase $PWD/$BIN 0x08001000" \
  -c "verify_image $PWD/$BIN 0x08001000" \
  -c "reset halt" \
  -c "mem2array v 32 0x08001000 2" \
  -c "reg msp \$v(0)" -c "reg pc \$v(1)" \
  -c "resume" -c "shutdown"
echo "✅ 已烧写 $BIN 并启动（每个候选脚 4 秒 + 1 秒全低分界，循环）"
