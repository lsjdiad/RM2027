#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把闭环 RAM 捕获取出来，画成 adc_zc 那种'波形 + 过零标注'的图。
用法: python3 zcw-plot.py <npz> [out.png]"""
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

SRC = sys.argv[1] if len(sys.argv) > 1 else '/tmp/cl_stop.npz'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/home/lpl/桌面/RM2027/adc_zc_cl.png'
z = np.load(SRC)
idx, trig = int(z['idx']), int(z['trig_idx'])
N = len(z['zcw_vph']); order = (np.arange(N) + idx) % N
G = lambda k: z[k][order]
vph = G('zcw_vph').astype(int); v0 = G('zcw_v0').astype(int)
d = vph - v0; st = G('zcw_step'); zc = G('zcw_zc')
toff = (trig - idx) % N
FS = 1e6 / 24000.0                      # 每样本 = 1 ADC 帧 = 41.67µs
t = (np.arange(N) - toff) * FS / 1000.0

ROLE = {1:('C','B','A'), 2:('A','B','C'), 3:('B','A','C'),
        4:('C','A','B'), 5:('A','C','B'), 6:('B','C','A')}

fig, ax = plt.subplots(2, 1, figsize=(16, 7.5), sharex=True,
                       gridspec_kw={'height_ratios': [2.2, 1]})

# ---- 上：delta 波形 + 过零标注（adc_zc 风格）----
a = ax[0]
a.plot(t, d, 'o-', ms=3.0, lw=1.0, color='#34495e', label='delta = 悬空相 − V0（判据实际用的量）')
a.axhline(0, color='gray', lw=0.9, ls=':')
a.axvline(0, color='#8e0000', lw=1.8, ls='--', label='交棒触发（ci 涨过门槛）')
zi = np.where(zc != 0)[0]
for p in zi:
    col = '#1e8449' if zc[p] == 1 else '#1f4e9c'
    a.axvline(t[p], color=col, lw=1.1, alpha=0.75)
    a.plot(t[p], d[p], '^' if zc[p] == 1 else 'v', ms=9, color=col, zorder=5)
# 代码认为过零后该切哪两相
chg = [i for i in range(1, N) if st[i] != st[i-1]]
for k, c in enumerate(chg):
    if 1 <= st[c] <= 6:
        fl, lo, hi = ROLE[st[c]]
        a.text(t[c] + 0.06, 140, f"step{st[c]} 高={hi} 低={lo} 浮={fl}",
               fontsize=6.5, color='#7d3c98')
a.legend(fontsize=8, loc='lower left', ncol=2)
a.set_ylabel('ADC 码'); a.grid(alpha=0.25)
a.set_title('闭环捕获：判据看的波形 + 代码认到的过零（▲升沿 ▼降沿）+ 过零后该切哪两相')

# ---- 下：step（同一时间轴，便于对齐）----
a = ax[1]
a.step(t, st, where='post', color='#7d3c98', lw=1.2)
for p in zi:
    a.plot(t[p], st[p] + (0.25 if zc[p] == 1 else -0.25), '^' if zc[p] == 1 else 'v',
           ms=8, color='#1e8449' if zc[p] == 1 else '#1f4e9c')
a.axvline(0, color='#8e0000', lw=1.8, ls='--')
a.set_ylim(0.3, 6.7); a.set_ylabel('step (1..6)')
a.grid(alpha=0.25); a.set_xlabel('距交棒触发时刻 (ms)')
plt.tight_layout()
plt.savefig(OUT, dpi=130)
print(f"图已存: {OUT}")
print(f"窗口 {N*FS/1000:.1f}ms（交棒触发前 {toff*FS/1000:.1f}ms / 后 {(N-toff)*FS/1000:.1f}ms）")
print(f"判据认到的过零 {len(zi)} 个：")
for p in zi:
    nx = [c for c in chg if c > p]
    tag = f"→ step{st[nx[0]]} 高={ROLE[st[nx[0]]][2]} 低={ROLE[st[nx[0]]][1]} 浮={ROLE[st[nx[0]]][0]}" if nx and 1 <= st[nx[0]] <= 6 else ""
    print(f"   @{p:>3} ({(p-toff)*FS/1000:>+6.2f}ms) {'升沿' if zc[p]==1 else '降沿'}  {tag}")
