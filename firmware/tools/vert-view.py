#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vert-view.py —— 六步【竖直偏移】的整体变化：把某个偏移表离线作用上去，看竖直结构变好还是变坏。

用法: python3 tools/vert-view.py <evt_run_*.csv>     （用同名 _win.npz，需补偿 OFF 的那一轮原始波形）

为什么这么画（口径）：
  · 判据用的信号 d = 悬空相 − V0；每步用【该步的相】算（避开 step 字节的滞后）
  · **必须跳过换相后 ~2 个采样的建立瞬态**（实测 VA 999→77→350），否则"中心/接缝"全是假的
  · 每步"竖直中心" m_s = 该段（跳瞬态后）的均值；接缝跳变 J_s = 下一段开头 − 本段结尾
  · 施加后的值：d' = d·g_s + o_s（g 用老表的千分比；只比较偏移的效果时 g 近似 1）

三栏：① 六步竖直中心 m_s（三种情况）—— 看"整体竖直结构"是变齐还是散
      ② 接缝跳变 J_s（逐接缝 + RMS）—— 补偿的目标就是让它→0
      ③ 每步过零位置（理想 0.500）—— 看相位被推到哪
"""
import sys, os
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

FLY = {1: 'c', 2: 'a', 3: 'b', 4: 'c', 5: 'a', 6: 'b'}
OLD = {1: -36, 2: 61, 3: -45, 4: 41, 5: -60, 6: 42}                 # 老表（±60 码）
AO = {1: -200, 2: 125, 3: -175, 4: 150, 5: -200, 6: 125}            # 自适应第 1 轮学到的
CASES = [('原始（无偏移）', {s: 0 for s in range(1, 7)}, '#2471a3'),
         ('老表 ±60 码', OLD, '#7f8c8d'),
         ('自适应学到 ±200/125', AO, '#c0392b')]


def segs_of(z, w):
    st = z['step'][w].astype(int); db = z['dbg'][w].astype(int)
    res = [i for i in range(1, 512) if db[i] < db[i - 1]]
    bnd = [0] + res + [512]; out = []
    for k in range(len(bnd) - 1):
        a, b = bnd[k], bnd[k + 1]
        if b - a < 8:
            continue
        s = int(np.bincount(st[a + 4:b - 2]).argmax())
        out.append((a, b, s))
    return out


def main():
    csvp = sys.argv[1]
    z = np.load(csvp.replace('.csv', '_win.npz'))
    NW = z['step'].shape[0]
    # 逐段收集：每步的 (中心, 结尾值), 以及"下一段开头"以算接缝
    seq = []          # [(step, e0, e1, zcpos)]
    for w in range(NW):
        segs = segs_of(z, w)
        for a, b, s in segs:
            seg = z['v' + FLY[s]][w][a:b].astype(float) - z['v0'][w][a:b].astype(float)
            skip = max(4, int(0.15 * len(seg)))
            ss = seg[skip:]
            if len(ss) < 4:
                continue
            zc = None
            if (ss.min() < 0 < ss.max()) or (ss.max() < 0 < ss.min()):
                ix = np.where(np.diff(np.sign(ss)) != 0)[0]
                if len(ix):
                    zc = (skip + ix[0]) / (len(seg) - 1)
            seq.append((s, float(np.mean(ss)), float(ss[0]), float(seg[-1]), zc))
    if len(seq) < 50:
        print('❌ 段太少'); return

    fig, ax = plt.subplots(1, 3, figsize=(19, 5.2))
    # ① 六步竖直中心
    a = ax[0]
    x = np.arange(6)
    for j, (name, tab, col) in enumerate(CASES):
        m = [np.median([c + tab[k] for (s, c, f, e, _) in seq if s == k]) for k in range(1, 7)]
        a.bar(x + (j - 1) * 0.27, m, 0.25, color=col, label=name)
    a.axhline(0, color='gray', lw=.8)
    a.set_xticks(x); a.set_xticklabels([f'step{k}' for k in range(1, 7)])
    a.set_ylabel('每步竖直中心 m_s（码）')
    a.set_title('① 【竖直整体】：六步中心 m_s\n（三种情况；越整齐越好）', fontsize=10)
    a.legend(fontsize=8); a.grid(alpha=.25, axis='y')
    # ② 接缝跳变
    a = ax[1]
    for j, (name, tab, col) in enumerate(CASES):
        # ★ 接缝 = 下一段的【开头（跳瞬态后）】 − 本段的【结尾】
        J = [(seq[i+1][2] + tab[seq[i+1][0]]) - (seq[i][3] + tab[seq[i][0]])
             for i in range(len(seq) - 1)]
        rms = np.sqrt(np.mean(np.array(J) ** 2))
        ax[1].hist(J, bins=60, range=(-300, 300), histtype='step', lw=1.4, color=col,
                   label=f'{name}  RMS={rms:.0f} 码')
    ax[1].axvline(0, color='gray', lw=.8)
    ax[1].set_xlabel('接缝跳变 J_s（码）'); ax[1].set_ylabel('接缝数')
    ax[1].set_title('② 接缝跳变分布（补偿目标 = 全部压到 0）', fontsize=10)
    ax[1].legend(fontsize=8); ax[1].grid(alpha=.25)
    # ③ 过零位置
    a = ax[2]
    for j, (name, tab, col) in enumerate(CASES):
        # 只画原始位置：偏移对"位置"的精确换算要逐点插值，这里给原始分布作参照
        pos = [np.median([zc for (s, c, f, e, zc) in seq if s == k and zc is not None])
               for k in range(1, 7)]
        if j == 0:
            a.bar(x, pos, 0.5, color=col, label='原始过零位置')
            a.axhline(0.5, color='#27ae60', ls='--', lw=1.2, label='理想 0.500')
    a.set_xticks(x); a.set_xticklabels([f'step{k}' for k in range(1, 7)])
    a.set_ylabel('过零在段内的位置'); a.set_ylim(0, 1)
    a.set_title('③ 过零位置（原始；理想 0.500）\n—— 全在 0.5 之后 ⇒ 系统性偏晚', fontsize=10)
    a.legend(fontsize=8); a.grid(alpha=.25, axis='y')
    fig.suptitle(f'六步竖直偏移的整体变化 —— 离线把偏移表作用在原始波形上   {os.path.basename(csvp)}',
                 fontsize=12.5)
    plt.tight_layout(rect=[0, 0, 1, 0.93])
    o = os.path.join(os.path.dirname(csvp) or '.', '竖直偏移_' + os.path.basename(csvp)[8:21] + '.png')
    plt.savefig(o, dpi=125)
    print('图 →', o)
    for name, tab, col in CASES:
        J = [((seq[i+1][2] + tab[seq[i+1][0]]) - (seq[i][3] + tab[seq[i][0]])) for i in range(len(seq)-1)]
        print(f'  {name:22s} 接缝跳变 RMS = {np.sqrt(np.mean(np.array(J)**2)):6.1f} 码')


main()
