#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ao-replay.py —— 离线重放【自适应电压偏移】的更新，画"实际生效偏移随时间的变化"（奇偶两色系）。

用法: python3 tools/ao-replay.py <事件CSV>

为什么要重放：固件只存了"当前偏移 + 改动次数"，**没有存时间序列**。但更新是确定性的，
而且 CSV 里有全部原料 ⇒ 可以逐事件精确重算。

关键事实（也是这版回路的 bug 所在）：
  CSV 里的 `thiszctime` = 固件的 `bemf_zc_time` = 【换相→过零】的拍数。
  **它是 0 ⇒ 这次换相根本没认到过零、是 1.5×ci 兜底硬踹的。**
  而误差算的是 `thiszctime − ci/2` ⇒ 没认到过零时读成 −ci/2 ≈ −1000 拍（"早得离谱"）
  ⇒ 回路朝错误方向修 ⇒ 偏移跑飞、可见性被毁。下面第二栏就是加"无过零就不动"这道闸后的结果。

更新规则（与固件一致）：
  target = 过零所在那一步 = ((step_event − 2) mod 6) + 1     （事件里的 step 是换相【之后】的新步）
  err    = thiszctime − ci/2                                  （正 = 过零偏晚）
  if |err| > DEAD:  d = sgn(奇−/偶+) × K × err / 1000 ；|d| ≤ STEPMAX ；累计 |o| ≤ CLAMP
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

K, DEAD, STEPMAX, CLAMP = 300, 120, 25, 250
ODD_C = {1: '#c0392b', 3: '#e67e22', 5: '#8e44ad'}      # 奇步：暖色系
EVEN_C = {2: '#2471a3', 4: '#16a085', 6: '#2c3e50'}     # 偶步：冷色系


def replay(rows, guard):
    off = {s: 0 for s in range(1, 7)}
    hist = {s: [] for s in range(1, 7)}
    chg = {s: 0 for s in range(1, 7)}
    for i, r in enumerate(rows):
        s_new = int(r['step']); ci = int(r['ci']); tz = int(r['thiszctime'])
        tgt = ((s_new - 2) % 6) + 1
        if guard and tz == 0:            # ★ 没认到过零 ⇒ 不动（这一栏是"修好后"的行为）
            hist[tgt].append(off[tgt]); continue
        err = tz - ci // 2
        if abs(err) > DEAD:
            sgn = -1 if (tgt & 1) else +1
            d = sgn * K * err // 1000
            d = max(-STEPMAX, min(STEPMAX, d))
            nv = max(-CLAMP, min(CLAMP, off[tgt] + d))
            if nv != off[tgt]:
                off[tgt] = nv; chg[tgt] += 1
        hist[tgt].append(off[tgt])
    return hist, chg


def main():
    csvp = sys.argv[1]
    import csv as _csv
    rows = list(_csv.DictReader(open(csvp)))
    stg = np.array([int(r['stage']) for r in rows])
    # 只重放【闭环段】(stage==0)：开环斜坡不产生更新
    idx = [i for i, s in enumerate(stg) if s == 0]
    rows_cl = [rows[i] for i in idx]
    h1, c1 = replay(rows_cl, guard=False)
    h2, c2 = replay(rows_cl, guard=True)

    fig, ax = plt.subplots(2, 1, figsize=(19, 9), sharex=False)
    for j, (h, chg, title) in enumerate((
            (h1, c1, f'① 实际发生（当前固件）：无过零被当成"过零太早" ⇒ 跑飞  '
                     f'改动合计 {sum(c1.values())} 次'),
            (h2, c2, f'② 加了"无过零就不动"这道闸之后：改动合计 {sum(c2.values())} 次'))):
        a = ax[j]
        for s in range(1, 7):
            c = ODD_C[s] if (s & 1) else EVEN_C[s]
            a.plot(np.arange(len(h[s])), h[s], lw=1.6, color=c,
                   label=f'step{s}（{"奇" if s & 1 else "偶"}）')
        a.axhline(0, color='gray', lw=.8)
        for y in (CLAMP, -CLAMP):
            a.axhline(y, color='#c0392b', ls=':', lw=1)
        a.set_ylabel('实际生效的偏移（码）')
        a.set_xlabel('闭环段内的第 n 次换相（时间顺序）')
        a.set_title(title, fontsize=10.5)
        a.legend(fontsize=8, ncol=6, loc='upper left'); a.grid(alpha=.25)
        # 底部条：这段里"无过零"的位置
        nz = [1 if int(r['thiszctime']) == 0 else 0 for r in rows_cl]
        a.fill_between(np.arange(len(nz)), -CLAMP * 1.12, -CLAMP * 1.06,
                       where=np.array(nz) == 1, color='#922b21', lw=0)
        a.text(10, -CLAMP * 1.02, '红条 = 该次换相【无过零】（兜底硬踹）', fontsize=8, color='#922b21')
    fig.suptitle(f'自适应电压偏移：实际生效值随时间的变化（奇=暖色 / 偶=冷色）   '
                 f'{os.path.basename(csvp)}', fontsize=13)
    plt.tight_layout(rect=[0, 0, 1, 0.95])
    o = os.path.join(os.path.dirname(csvp) or '.', '偏移时间线_' + os.path.basename(csvp)[8:21] + '.png')
    plt.savefig(o, dpi=125)
    print('图 →', o)
    print(f'  实际（无闸）：改动 {sum(c1.values())} 次  末值 ' +
          ' '.join(f's{s}:{list(h1[s])[-1] if h1[s] else 0}' for s in range(1, 7)))
    print(f'  加闸之后    ：改动 {sum(c2.values())} 次  末值 ' +
          ' '.join(f's{s}:{list(h2[s])[-1] if h2[s] else 0}' for s in range(1, 7)))
    nzr = 100 * np.mean([1 if int(r['thiszctime']) == 0 else 0 for r in rows_cl])
    print(f'  闭环段无过零比例 {nzr:.0f}%')


main()
