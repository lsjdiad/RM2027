#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evt-plot.py —— 把串口事件流画成"闭环全过程"图，一眼看清"抖"和"越来越慢"。
用法: python3 evt-plot.py <csv> [输出png]

四栏自上而下：换相间隔 / 转速 / 占空比+电流 / step
背景按时间段上色：绿=还正常、黄=开始抖、红=塌陷。
"""
import sys
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

f = sys.argv[1] if len(sys.argv) > 1 else '/home/lpl/桌面/RM2027/evt_20261011_220529.csv'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/home/lpl/桌面/RM2027/闭环全过程.png'

a = np.loadtxt(f, delimiter=',', skiprows=1, dtype=np.int64)
seq, ts, delta, step, wait, dut, cur = (a[:, i] for i in range(7))

# 剔除传输错帧
dseq = np.diff(seq, prepend=seq[0] - 1)
dts = np.diff(ts, prepend=ts[0])
ok = ((step >= 1) & (step <= 6) & (dut <= 2000) & (np.abs(delta) < 3000)
      & (cur >= 0) & (cur < 400) & (dseq == 1) & (dts > 0) & (dts < 24000))
a, seq, ts, delta, step, wait, dut, cur = (x[ok] for x in (a, seq, ts, delta, step, wait, dut, cur))
print('有效事件 %d（剔除错帧 %d）' % (len(a), (~ok).sum()))

t = (ts - ts[0]) / 24000.0                   # 秒
iv = np.diff(ts) / 24000.0 * 1000.0          # ms
tt = t[1:]
rpm = 60.0 / (iv * 6 / 1000.0) / 6.0         # 机械转速（6 极对）

fig, ax = plt.subplots(4, 1, figsize=(16, 12), sharex=True,
                       gridspec_kw={'height_ratios': [1.3, 1, 1, 0.9]})
for A in ax:
    A.axvspan(0, 2,  color='#eafaf1', zorder=0, label='正常')
    A.axvspan(2, 5,  color='#fef9e7', zorder=0, label='开始抖')
    A.axvspan(5, t[-1] + 1, color='#fdedec', zorder=0, label='塌陷')
    A.grid(alpha=0.25)

ax[0].plot(tt, iv, lw=0.7, color='#c0392b')
ax[0].axhline(1.0, color='gray', ls='--', lw=1.0, label='1.000 ms（与开环同速）')
ax[0].set_ylabel('换相间隔 (ms)')
ax[0].set_title('闭环全过程：为什么"抖且越来越慢"   （绿=正常 黄=开始抖 红=塌陷）')
ax[0].legend(fontsize=9, ncol=4)

ax[1].plot(tt, rpm, lw=0.7, color='#2980b9')
ax[1].axhline(1670, color='#27ae60', ls='--', lw=1.0, label='开环 1670 转/分')
ax[1].set_ylabel('转速 (转/分)'); ax[1].legend(fontsize=9)

ax[2].plot(t, dut * 100 / 2000.0, lw=0.7, color='#16a085', label='占空比 (%)')
ax[2].axhline(20.1, color='#c0392b', ls=':', lw=1.2, label='我加的上限 20%')
ax[2].set_ylabel('占空比 (%)'); ax[2].legend(fontsize=9, loc='upper left')
ax2b = ax[2].twinx()
ax2b.plot(t, cur, lw=0.7, color='#e67e22', alpha=0.85, label='电流')
ax2b.set_ylabel('电流', color='#e67e22'); ax2b.tick_params(axis='y', colors='#e67e22')
ax2b.legend(fontsize=9, loc='upper right')

ax[3].step(t, step, where='post', lw=0.7, color='#8e44ad')
ax[3].set_ylim(0.5, 6.5); ax[3].set_ylabel('step (1..6)')
ax[3].set_xlabel('交棒后的时间 (s)')

ax[-1].set_xlim(-0.2, min(t[-1] + 1.0, 20.0))   # 只画有数据的范围
plt.tight_layout()
plt.savefig(OUT, dpi=130)
print('图已存:', OUT)
