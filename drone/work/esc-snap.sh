#!/bin/bash
# esc-snap.sh —— 电调台架状态快照（SWD，非侵入式读 RAM）
#
# ★★ 四个必须遵守的点（都是踩过的坑）★★
#   ① 变量地址每次编译都会漂 ⇒ 必须从当前 ELF 现取，不能硬编码
#   ② 本固件开着 IWDG（≈512ms），喂狗只在主循环/PWM 中断里 ⇒ halt 超过约半秒
#      必被复位，pc 会停在 bootloader 入口 0x08000104，看着像"app 没跑"。
#      修法：halt 之后立刻写 IWDG_KR(0x40003000)=0xAAAA 喂一次狗。
#   ③ mdw 写在 -f 脚本文件里不输出 ⇒ dump 数组必须用 -c "mdw ..."
#   ④ ★ 不同分支的变量名不一样（比如开环分支没有 adc_zc_*/ol_startup_arm）
#      ⇒ 不能写死字段清单，否则整条 openocd 命令会因为空地址而失败。
#      本脚本改成【按符号是否存在动态生成读取列表】。
#
# 用法： ./esc-snap.sh        读一次
set -u
ELF=/home/lpl/桌面/RM2027/AM32-rm2027/obj/AM32_RM2027_ESC_G071_2.21.elf
NM=/usr/bin/arm-none-eabi-nm
[ -f "$ELF" ] || { echo "❌ 找不到 $ELF，先编译"; exit 1; }

# (显示名, 符号名, 宽度 b=u8 h=u16 w=u32)
FIELDS="
bat battery_voltage h
duty duty_cycle h
cur actual_current h
run running b
oldr old_routine b
arm ol_startup_arm b
stage ol_startup_stage b
ozc ol_startup_zc b
steps ol_steps w
div ol_step_div_cur h
ver ol_verify_ok b
soak ol_soak_ticks w
zc zero_crosses w
to bemf_timeout_happened b
ci commutation_interval w
iov input_override w
adv advance h
tadv temp_advance b
avg average_interval w
wait waitTime h
vph bemf_adc_vph h
v0 bemf_adc_v0 h
zcr adc_zc_n_rise w
zcf adc_zc_n_fall w
zcj adc_zc_n_reject w
zce adc_zc_ev_idx b
ostate ol_state b
otick ol_ticks h
otc ol_trip_count h
otrips ol_trips w
stop ol_stop_reason b
ssite ol_stop_site b
dsc desync_happened w
otmo ol_timeouts w
"

TCL=$(mktemp /tmp/esc-snap-XXXXXX.tcl)
echo 'proc RV {a sh msk} { expr {(([mrw $a] >> $sh) & $msk)} }' > "$TCL"
echo 'halt' >> "$TCL"
echo 'mww 0x40003000 0xAAAA' >> "$TCL"
PROG=""
echo "$FIELDS" | while read -r nm sym w; do
  [ -z "${nm:-}" ] && continue
  A=$($NM "$ELF" | awk -v s="$sym" '$3==s {print "0x"$1; exit}')
  [ -z "$A" ] && continue                      # 本分支没有这个符号 ⇒ 跳过
  # ★ mrw 要求【字对齐】！u16/u8 常常落在字的另一半（例如 bemf_adc_v0 在 0x…3ea）
  #   ⇒ 直接 mrw 会报错并中断整个脚本。做法：对齐到字读，再按字内偏移取对半。
  #   统一用一个 proc RV {addr shift mask}，避免把 expr 嵌套进 format 里（那样会断）。
  AA=$(( A & ~3 ))
  case "$w" in
    b) EXPR="[RV $AA $(( (A & 3) * 8 )) 0xFF]" ;;
    h) EXPR="[RV $AA $(( (A & 2) * 8 )) 0xFFFF]" ;;
    *) EXPR="[mrw $A]" ;;
  esac
  echo "echo [format {$nm=%d } $EXPR]" >> "$TCL"
done
echo 'echo ""' >> "$TCL"
echo 'mww 0x40003000 0xAAAA' >> "$TCL"
echo 'resume' >> "$TCL"

timeout 60 openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "adapter speed 1800" -c "init" -f "$TCL" -c "shutdown" 2>&1 \
  | grep -aE "^[a-z0-9]+=" | sed 's/ *$//'
rm -f "$TCL"
