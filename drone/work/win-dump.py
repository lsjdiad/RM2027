#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
win-dump.py —— 接收电调的【窗口式全速采样】并画电压/转速/过零三合一图。
用法: python3 win-dump.py [串口] [秒数]

固件侧（Src/main.c 的 win_push/win_pump）：
  窗口内 24kHz 全速采 512 帧（21.3ms），窗口之间把整窗用串口发出来。
  每窗一包：A5 5A A5 5A | seq u16 | ts u32 | n u16 | n*(delta i16 + step u8)
    ts   = 本窗首帧的 24kHz 总帧号（41.67us/格）—— 对齐时间轴用
    delta= 悬空相 − V0（ADC 码）；step = 1..6
  覆盖率约 58%（采集 21.3ms + 发送 15.5ms 一轮）。
"""
import sys, glob, struct, time
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager

for _f in ('Noto Sans CJK SC', 'Noto Sans CJK JP'):
    if any(_f in f.name for f in font_manager.fontManager.ttflist):
        plt.rcParams['font.family'] = _f
        break
plt.rcParams['axes.unicode_minus'] = False

PORT = sys.argv[1] if len(sys.argv) > 1 else None
SECS = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0
BAUD = 1000000
if PORT is None:
    c = sorted(glob.glob('/dev/ttyUSB*')) + sorted(glob.glob('/dev/ttyACM*'))
    if not c:
        print("❌ 没找到串口"); sys.exit(1)
    PORT = c[0]

import serial
ser = serial.Serial(PORT, BAUD, timeout=1.0)
ser.reset_input_buffer()
print(f"串口 {PORT} @ {BAUD}，收 {SECS} 秒 ...")

buf = bytearray(); wins = []
t0 = time.time()
while time.time() - t0 < SECS:
    ch = ser.read(8192)
    if ch:
        buf += ch
    while True:
        i = buf.find(b'\xA5\x5A\xA5\x5A')
        if i < 0:
            if len(buf) > 3: del buf[:-3]
            break
        if len(buf) - i < 12:
            del buf[:i]; break
        seq, ts, n = struct.unpack_from('<HIH', buf, i + 4)
        if n == 0 or n > 1024:
            del buf[:i + 1]; continue
        need = 12 + n * 3
        if len(buf) - i < need:
            del buf[:i]; break
        pay = bytes(buf[i + 12:i + need])
        wins.append((seq, ts, np.frombuffer(pay, dtype=np.uint8).reshape(n, 3)))
        del buf[:i + need]
ser.close()

if not wins:
    print("❌ 没收到窗口 —— 检查波特率 1Mbaud / 接线 RX 对 PB6 / 电机是否在转")
    sys.exit(1)

print(f"收到 {len(wins)} 个窗口，每个 {wins[0][2].shape[0]} 帧")
seqs = [w[0] for w in wins]
lost = sum(1 for a, b in zip(seqs, seqs[1:]) if b != (a + 1) & 0xFFFF)
print(f"窗口序号不连续：{lost} 处（丢窗）")

# 拼时间轴（按 ts，各窗内部 41.67us/帧）
MS = 1000.0 / 24000.0
T, D, S = [], [], []
for seq, ts, p in wins:
    dl = p[:, 0].astype(np.int16) | (p[:, 1].astype(np.int16) << 8)
    st = p[:, 2]
    tt = ts * MS + np.arange(len(dl)) * MS
    T.append(tt); D.append(dl); S.append(st)
T = np.concatenate(T); D = np.concatenate(D); S = np.concatenate(S)
T = T - T[0]
print(f"总帧 {len(T)}，时间跨度 {T[-1]:.2f} 秒（覆盖率约 58%，窗与窗之间有间隔）")

# 过零（用判据同样的规则：变号 + 斜率上限）
zi = []
for k in range(1, len(D)):
    if (D[k-1] <= 0 < D[k]) or (D[k-1] >= 0 > D[k]):
        if abs(int(D[k]) - int(D[k-1])) <= 100:
            zi.append(k)
zi = np.array(zi, dtype=int)
print(f"其中过零 {len(zi)} 次")

ch = np.where(np.diff(S) != 0)[0] + 1
rpm = np.array([])
if len(ch) > 2:
    gap = np.diff(T[ch])
    gap = gap[gap > 0.05]
    if len(gap):
        rpm = 60.0 / (gap * 6 / 1000.0) / 6.0
        print(f"转速：中位 {np.median(rpm):.0f} 转/分（开环 1670）  最小 {rpm.min():.0f}  最大 {rpm.max():.0f}")

fig, ax = plt.subplots(3, 1, figsize=(16, 10), sharex=True,
                       gridspec_kw={'height_ratios': [2.2, 1.0, 0.8]})
ax[0].plot(T, D, '-', lw=0.9, color='#2c3e50', label='悬空相 − V0')
ax[0].axhline(0, color='gray', lw=0.7, ls=':')
for p in zi:
    ax[0].axvline(T[p], color='#27ae60', lw=0.9, alpha=0.7)
for p in ch:
    ax[0].axvline(T[p], color='#c0392b', lw=0.9, ls='--', alpha=0.6)
ax[0].plot([], [], color='#27ae60', lw=1.4, label='过零（判据规则）')
ax[0].plot([], [], color='#c0392b', lw=1.4, ls='--', label='换相（step 变化）')
ax[0].set_ylabel('ADC 码'); ax[0].legend(fontsize=9); ax[0].grid(alpha=0.25)
ax[0].set_title('串口窗口式全速采样：电压 + 过零 + 换相（%d 窗，覆盖率约 58%%）' % len(wins))
if len(rpm):
    ax[1].plot(T[ch][1:][:len(rpm)], rpm, 'o-', ms=3, lw=1.0, color='#2980b9')
    ax[1].axhline(1670, color='#27ae60', ls='--', lw=1.0, label='开环 1670')
    ax[1].set_ylabel('转速 (转/分)'); ax[1].legend(fontsize=9)
ax[1].grid(alpha=0.25)
ax[2].step(T, S, where='post', lw=0.9, color='#8e44ad')
ax[2].set_ylim(0.5, 6.5); ax[2].set_ylabel('step'); ax[2].grid(alpha=0.25)
ax[2].set_xlabel('时间 (s)')
plt.tight_layout()
OUT = '/home/lpl/桌面/RM2027/窗口采样.png'
plt.savefig(OUT, dpi=130)
print('图已存:', OUT)
