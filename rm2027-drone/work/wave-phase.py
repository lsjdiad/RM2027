#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wave-phase.py —— 把原始波形画出来，重点是看【换相点相对过零点偏了多少】。
用法: python3 wave-phase.py [npz] [输出png]

npz 由 zcw-dump.py 从电调 RAM 里 dump 得到，含：
  d = 悬空相 − V0（每 41.67us 一点）  step = 当时的换相步号  zc = 判据认到的过零(0/1升/2降)

图上三类竖线：
  绿实线 = 判据认到的过零时刻
  红虚线 = 换相时刻（step 变化处）
  理想：每个换相点应落在【上一次过零之后半步】处（换相步宽的一半）。
如果红色明显偏在绿色后面很远，就是"相位滞后" —— 会产生反向转矩、效率暴跌。
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
OUT = sys.argv[2] if len(sys.argv) > 2 else '/home/lpl/桌面/RM2027/波形相位.png'

z = np.load(NPZ)
d = z['d'].astype(float)
step = z['step'].astype(int)
zc = z['zc'].astype(int)
MS = 1000.0 / 24000.0          # 每点 0.04167 ms
t = np.arange(len(d)) * MS

zi = np.where(zc != 0)[0]                       # 判据认到的过零
ch = np.where(np.diff(step) != 0)[0] + 1        # 换相（step 变化）
ROLE = {1: '高A低B浮C', 2: '高C低B浮A', 3: '高C低A浮B',
        4: '高B低A浮C', 5: '高B低C浮A', 6: '高A低C浮B'}

print('波形 %d 点 = %.1f ms ；认到过零 %d 次 ；换相 %d 次'
      % (len(d), len(d) * MS, len(zi), len(ch)))

# ---- 量相位：每次换相，找它之前最近的一次过零 ----
rows = []
for c in ch:
    prev = zi[zi < c]
    if len(prev) == 0:
        continue
    z0 = prev[-1]
    # 该换相步的宽度：上一个换相到这一个换相
    prevc = ch[ch < c]
    w = (c - prevc[-1]) * MS if len(prevc) else np.nan
    rows.append((t[z0], t[c], (t[c] - t[z0]), w, step[c]))
if rows:
    a = np.array([(r[0], r[1], r[2], r[3]) for r in rows])
    lat = a[:, 2]
    wid = a[:, 3]
    good = np.isfinite(wid) & (wid > 0)
    ratio = lat[good] / wid[good]
    print('\n过零 -> 换相 的延迟：中位 %.3f ms  均值 %.3f ms' % (np.median(lat), lat.mean()))
    print('该延迟 / 换相步宽 的比值：中位 %.3f   （理想 = 0.50，即过零后 30 度换相）'
          % np.median(ratio))
    if np.median(ratio) > 0.7:
        print('  ⇒ 比值明显大于 0.5：换相【滞后】于理想位置 ⇒ 会产生反向转矩 ⇒ 效率掉')
    elif np.median(ratio) < 0.3:
        print('  ⇒ 比值明显小于 0.5：换相【提前】⇒ 同样产生反向转矩')
    else:
        print('  ⇒ 相位接近理想（0.5）')

fig, ax = plt.subplots(2, 1, figsize=(16, 8.5), sharex=True,
                       gridspec_kw={'height_ratios': [2.1, 1]})
ax[0].plot(t, d, '-', lw=1.1, color='#2c3e50', label='delta = 悬空相 − V0')
ax[0].axhline(0, color='gray', lw=0.7, ls=':')
for p in zi:
    ax[0].axvline(t[p], color='#27ae60', lw=1.0, alpha=0.75)
    ax[0].plot(t[p], d[p], '^' if zc[p] == 1 else 'v', color='#27ae60', ms=6, zorder=5)
for p in ch:
    ax[0].axvline(t[p], color='#c0392b', lw=1.1, ls='--', alpha=0.75)
    if 1 <= step[p] <= 6:
        ax[0].text(t[p] + 0.03, 160, 's%d %s' % (step[p], ROLE[step[p]]),
                   fontsize=6, color='#c0392b', rotation=90, va='top')
ax[0].plot([], [], color='#27ae60', lw=1.4, label='判据认到的过零')
ax[0].plot([], [], color='#c0392b', lw=1.4, ls='--', label='换相时刻（step 变化）')
ax[0].set_ylabel('ADC 码'); ax[0].grid(alpha=0.25)
ax[0].set_title('原始波形 + 过零点 + 换相点：理想换相应落在【过零后半步】(绿=过零 红=换相)')
ax[0].legend(fontsize=9, loc='lower left')

ax[1].step(t, step, where='post', lw=1.0, color='#8e44ad')
for p in zi:
    ax[1].axvline(t[p], color='#27ae60', lw=1.0, alpha=0.75)
for p in ch:
    ax[1].axvline(t[p], color='#c0392b', lw=1.1, ls='--', alpha=0.75)
ax[1].set_ylim(0.5, 6.5); ax[1].set_ylabel('step (1..6)')
ax[1].set_xlabel('时间 (ms)'); ax[1].grid(alpha=0.25)

plt.tight_layout()
plt.savefig(OUT, dpi=130)
print('\n图已存:', OUT)
