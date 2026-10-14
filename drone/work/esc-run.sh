#!/bin/bash
# esc-run.sh —— 电调一键：烧写 + 手工启动 app + 状态回读
#   背景：本板 bootloader 不主动跳 app（见 ESC-plan-task_plan.md 阶段 F），
#         台架期用 SWD 手工装 SP/PC 绕过。
#   用法： ./esc-run.sh          烧写并启动
#          ./esc-run.sh status   只回读状态（不烧）
#   前置： ST-Link 插在电调 SWD 上、电调已由 3.3V 供电
set -u
fw="${FW:-/tmp/am32-fw.bin}"
TARGET=target/stm32g0x.cfg
oc() { timeout 120 openocd -f interface/stlink.cfg -f "$TARGET" -c "adapter speed 500" "$@" 2>&1; }

if ! lsusb | grep -q 0483; then
  echo "❌ ST-Link 不在 USB 上 —— 请插上"; exit 1
fi

if [ "${1:-run}" = "status" ]; then
  oc -c "init" -c "halt" -c "reg pc" \
     -c "mdw 0x200003c8 4" -c "mdw 0x2000067c 4" -c "mdw 0x20000798 8" \
     -c "shutdown" | grep -aE "pc \(|^0x2"
  exit 0
fi

[ -f "$fw" ] || { echo "❌ 找不到固件 $fw"; exit 1; }
echo "▶ 烧写 $fw → 0x08001000"
oc -c "init" -c "halt" -c "flash write_image erase $fw 0x08001000" | grep -aiE "error|wrote" || true
echo "▶ ★ 补写 bootloader 的「app 有效」标志（*(0x0801F800) = 1）"
# 根因见 ESC-bootloader-不跳app-根因与修复.md：
#   bootloader 在 0x0800046c 检查 *(0x0801F800)==1 才跳 app。
#   用 SWD 直烧 app 会绕过 bootloader，导致该标志不被写 ⇒ 每次上电卡在 bootloader。
if [ -f /tmp/eeprom_fixed.bin ]; then
  oc -c "init" -c "halt" \
     -c "flash write_image erase /tmp/eeprom_fixed.bin 0x0801F800" | grep -aiE "error" || true
else
  echo "  ⚠️ 缺 /tmp/eeprom_fixed.bin，跳过（可后补：见文档第 4 节）"
fi

echo "▶ 手工装 app 向量并启动"
oc -c "init" -c "halt" \
   -c "mem2array v 32 0x08001000 2" -c "reg msp \$v(0)" -c "reg pc \$v(1)" \
   -c "resume" -c "shutdown" | grep -aiE "error" || true
echo "▶ 启动完成，2 秒后回读（pc 应落在 0x08001xxx）"
sleep 2
"$0" status
