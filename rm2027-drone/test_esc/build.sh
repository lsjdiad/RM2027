#!/bin/bash
# 一键：配置 + 编译（+ 可选烧写）。用法：
#   ./build.sh                # 只编译
#   ./build.sh flash          # 编译并烧写（默认走 J-Link / SWD）
#   IFACE=stlink ./build.sh flash   # 换 ST-Link 烧
#
# ★ 烧写工具必须接在【这块 F103】上，不是电调板！
set -e
cd "$(dirname "$0")"
cmake --preset Debug
cmake --build --preset Debug
arm-none-eabi-size build/Debug/test_esc.elf

if [ "${1:-}" = "flash" ]; then
  IFACE="${IFACE:-jlink}"

  if [ "$IFACE" = "stlink" ]; then
    echo "▶ 烧写 F103（ST-Link）"
    openocd -f interface/stlink.cfg -f target/stm32f1x.cfg \
      -c "program build/Debug/test_esc.elf verify reset exit"
  else
    # J-Link 走 SWD：必须显式 transport select swd，
    # 否则 openocd 默认 JTAG，会报 "JTAG scan chain interrogation failed: all ones"
    echo "▶ 烧写 F103（J-Link / SWD）"
    openocd -f interface/jlink.cfg -c "transport select swd" \
      -f target/stm32f1x.cfg -c "adapter speed 1000" \
      -c "program build/Debug/test_esc.elf verify reset exit"
  fi
fi
