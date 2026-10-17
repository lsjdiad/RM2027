#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cl-summary.py —— 一张图看闭环：电压波形 + 转速 + 过零检测（共享时间轴）。
用法: python3 cl-summary.py [npz] [输出png]

三栏自上而下、时间轴对齐：
  ① 悬空相电压 delta = 悬空相 − V0（这就是判据用的那路反电势）
     绿实线 = 判据认到的过零  红虚线 = 换相时刻（step 变化）  紫字 = 该步的角色
  ② 转速（转/分）—— 由相邻两次换相的时间差换算
  ③ 过零检测结论：▲=上升过零 ▼=下降过零（判据输出）
竖直灰线 = 交棒时刻（左侧是开环起步链，右侧是闭环）
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

NPZ = sys.argv[1] if len(sys.argv) > 1 else '/tmp/zcw.npz'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/home/lpl/桌面/RM2027/闭环综合.png'

z = np.load(NPZ)
d = z['d'].astype(float)
step = z['step'].astype(int)
zc = z['zc'].astype(int)
trig_off = int(z['trig_off']) if 'trig_off' in z else 0
MS = 1000.0 / 24000.0
t = (np.arange(len(d)) - trig_off) * MS      # 0 = 交棒时刻

zi = np.where(zc != 0)[0]
ch = np.where(np.diff(step) != 0)[0] + 1
ROLE = {1: '高A低B浮C', 2: '高C低B浮A', 3: '高C低A浮B',
        4: '高B低A浮C', 5: '高B低C浮A', 6: '高A低C浮B'}

# 转速：相邻换相的时间差 -> 转/分（6 极对）
if len(ch) > 2:
    gap_ms = np.diff(t[ch])                    # 每步耗时
    rpm = 60.0 / (gap_ms * 6 / 1000.0) / 6.0
    tc = t[ch][1:]
else:
    gap_ms = np.array([np.nan]); rpm = np.array([np.nan]); tc = np.array([0.0])

print('波形 %d 点 = %.1f ms ；过零 %d 次 ；换相 %d 次' % (len(d), len(d)*MS, len(zi), len(ch)))
if len(rpm) > 2:
    print('转速：中位 %.0f 转/分  最小 %.0f  最大 %.0f' % (np.median(rpm), rpm.min(), rpm.max()))
    print('每步耗时：中位 %.3f ms  最小 %.3f  最大 %.3f' % (np.median(gap_ms), gap_ms.min(), gap_ms.max()))
    # 每个换相步里认到几次过零（理想 1 次）
    cnt = []
    for i in range(len(ch) - 1):
        cnt.append(((zi > ch[i]) & (zi <= ch[i+1])).sum())
    cnt = np.array(cnt)
    print('每个换相步内认到的过零次数：中位 %d   （理想 1）  分布 %s'
          % (np.median(cnt), dict(zip(*np.unique(cnt, return_counts=True)))))

fig, ax = plt.subplots(3, 1, figsize=(16, 10), sharex=True,
                       gridspec_kw={'height_ratios': [2.2, 1.0, 0.8]})
ax[0].plot(t, d, '-', lw=1.1, color='#2c3e50', label='悬空相 − V0（判据用的反电势）')
ax[0].axhline(0, color='gray', lw=0.7, ls=':')
for p in zi:
    ax[0].axvline(t[p], color='#27ae60', lw=1.0, alpha=0.7)
    ax[0].plot(t[p], d[p], '^' if zc[p] == 1 else 'v', color='#27ae60', ms=6, zorder=5)
for p in ch:
    ax[0].axvline(t[p], color='#c0392b', lw=1.1, ls='--', alpha=0.7)
    if 1 <= step[p] <= 6:
        ax[0].text(t[p] + 0.03, 170, ROLE[step[p]], fontsize=6, color='#7d3c98',
                   rotation=90, va='top')
ax[0].axvline(0, color='black', lw=1.6, alpha=0.85, label='交棒（右=闭环）')
ax[0].plot([], [], color='#27ae60', lw=1.4, label='判据认到的过零')
ax[0].plot([], [], color='#c0392b', lw=1.4, ls='--', label='换相时刻')
ax[0].set_ylabel('ADC 码'); ax[0].grid(alpha=0.25)
ax[0].set_title('闭环阶段一张图：电压波形 + 转速 + 过零检测   （灰线右侧 = 闭环）')
ax[0].legend(fontsize=9, loc='lower left', ncol=2)

ax[1].plot(tc, rpm, 'o-', ms=3.5, lw=1.0, color='#2980b9')
ax[1].axhline(1670, color='#27ae60', ls='--', lw=1.0, label='开环 1670 转/分')
ax[1].set_ylabel('转速 (转/分)'); ax[1].legend(fontsize=9); ax[1].grid(alpha=0.25)

ax[2].plot(t[zi], np.where(zc[zi] == 1, 1, -1), 'o', ms=5,
           color='#16a085', label='过零检测输出（▲升 ▼降）')
ax[2].axhline(0, color='gray', lw=0.7, ls=':')
ax[2].set_ylim(-1.6, 1.6); ax[2].set_yticks([-1, 0, 1]); ax[2].set_yticklabels(['降', '0', '升'])
ax[2].set_ylabel('过零检测'); ax[2].legend(fontsize=9); ax[2].grid(alpha=0.25)
ax[2].set_xlabel('距交棒时刻 (ms)')

plt.tight_layout()
plt.savefig(OUT, dpi=130)
print('\n图已存:', OUT)
