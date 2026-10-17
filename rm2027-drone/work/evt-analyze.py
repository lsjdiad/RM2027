#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evt-analyze.py —— 分析串口事件流 CSV：按【交棒后的时间分段】看抖动与电流。
用法: python3 evt-analyze.py <csv>

为什么要分时段：用户观察"交棒之后抖动特别明显，而且闭环电流特别大"，
而内存记录只有 1 秒多、可能正好错过那一段。这里直接按时间为段统计。
"""
import sys
import numpy as np

f = sys.argv[1] if len(sys.argv) > 1 else '/home/lpl/桌面/RM2027/evt_20261011_220529.csv'
a = np.loadtxt(f, delimiter=',', skiprows=1, dtype=np.int64)
seq, ts, delta, step, wait, dut, cur = (a[:, i] for i in range(7))
print('总行数 %d' % len(a))

# --- 合理性筛选：踢掉传输错帧 ---
dseq = np.diff(seq, prepend=seq[0] - 1)
dts = np.diff(ts, prepend=ts[0])
ok = ((step >= 1) & (step <= 6) & (dut <= 2000) & (np.abs(delta) < 3000)
      & (cur >= 0) & (cur < 400) & (dseq == 1) & (dts > 0) & (dts < 24000))
print('剔除错帧后剩 %d 行（剔除 %d）' % (ok.sum(), (~ok).sum()))

a, seq, ts, delta, step, wait, dut, cur = (x[ok] for x in (a, seq, ts, delta, step, wait, dut, cur))
t = (ts - ts[0]) / 24000.0            # 秒
iv = np.diff(ts) / 24000.0 * 1000.0   # ms（相邻事件间隔）
tt = t[1:]

print('\n%8s %8s %8s %8s %8s %8s %8s' % ('时段(s)', '事件数', '间隔中位', '间隔均值', '标准差', '占空比', '电流'))
print('%8s %8s %8s %8s %8s %8s %8s' % ('', '', '(ms)', '(ms)', '(ms)', '(中位)', '(中位/最大)'))
segs = [(0, 0.3), (0.3, 0.6), (0.6, 1.0), (1.0, 2.0), (2.0, 5.0), (5.0, 10.0), (10.0, 99.0)]
for lo, hi in segs:
    m = (tt >= lo) & (tt < hi)
    if m.sum() < 3:
        continue
    print('%4.1f-%-4.1f %8d %8.3f %8.3f %8.3f %8.0f %8.0f/%-4.0f'
          % (lo, hi, m.sum(), np.median(iv[m]), iv[m].mean(), iv[m].std(),
             np.median(dut[1:][m]), np.median(cur[1:][m]), cur[1:][m].max()))

print('\n峰值：电流最大 %d（电调内部单位；110 约 1.8A）  占空比最大 %d/2000 = %.1f%%'
      % (cur.max(), dut.max(), dut.max()*100/2000))
print('平均换相间隔 %.3f ms => %.0f 转/分（6 极对）' % (iv.mean(), 60.0/(iv.mean()*6/1000.0)/6))
