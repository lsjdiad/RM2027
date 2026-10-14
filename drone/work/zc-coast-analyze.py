#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''滑行（coast）捕获分析：从触发时刻起，纯反电势的频率与幅值随时间怎么走。

数据来源：固件 zcw_* 多窗口捕获，zcw-dump.py 存成 /tmp/zcw.npz
  第 0 窗是触发前的滚动环（已由 dump 脚本按 trig_idx 旋转还原）
  => rolled[255] 就是触发那一帧，t=0；后面是触发后线性填充的 3 窗。

要回答：
  ① 滑行 BEMF 的半电周期  vs  收油门前的半电周期（= 3 x commutation_interval）
  ② 幅值随滑行是不是跟着频率一起衰减
  ③ 判据（固件 adc_zc）在纯反电势上认到的过零位置对不对
'''
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

FS_US = 1e6 / 24000.0          # 41.6667 us/点
N = 256
WIN = 4
TOT = N * WIN                  # 1024

# --- 收油门前最后一个换相间隔（由 esc-snap.sh 读到的 ci，单位 0.5us）---
CI_TICKS = float(sys.argv[1]) if len(sys.argv) > 1 else 5281.0
ci_us = CI_TICKS * 0.5
half_elec_us = 3.0 * ci_us     # 半电周期 = 3 个换相步（60 度 x 3 = 180 度）
print('收油门前：换相间隔 ci = %.0f tick = %.3f ms' % (CI_TICKS, ci_us / 1000.0))
print('          => 半电周期 3xci = %.3f ms ；电周期 6xci = %.3f ms'
      % (half_elec_us / 1000.0, 2 * half_elec_us / 1000.0))

# --- 取数组 ---
z = np.load('/tmp/zcw.npz')
print('npz 字段:', {k: (z[k].shape, str(z[k].dtype)) for k in z.keys()})
d = None
for k in z.keys():
    a = z[k]
    if a.ndim == 1 and a.shape[0] == TOT and a.dtype == np.int16:
        d = a.astype(np.float64)
        print('波形字段 = %s' % k)
        break
if d is None:
    raise SystemExit('没找到 (1024,) int16 的波形字段')

step = None
for k in z.keys():
    a = z[k]
    if a.ndim == 1 and a.shape[0] == TOT and a.dtype == np.uint8:
        if a.max() <= 6 and a.min() >= 1:
            step = a
            print('step 字段 = %s' % k)
            break

t_ms = (np.arange(TOT) - (N - 1)) * FS_US / 1000.0     # rolled[255] 为 t=0
trig_i = N - 1

# ---------- 滑行段：找零交叉 ----------
# 触发后 step 应冻结；取 step 不再变的点作为"纯滑行"起点
t0_i = trig_i
if step is not None:
    s = step[trig_i:]
    # 最后一个 step 变化的位置之后就是纯滑行
    ch = np.nonzero(np.diff(s) != 0)[0]
    if len(ch):
        t0_i = trig_i + ch[-1] + 1
start_i = t0_i
print('\n纯滑行起点 = 第 %d 点 (t = %.2f ms)，此后 step 恒为 %s'
      % (start_i, t_ms[start_i], step[start_i] if step is not None else '?'))

seg = d[start_i:]
ts = t_ms[start_i:]

# 噪声闸：用滑行段的摆幅定一个阈值，避免把噪声反复穿零算成过零
amp_peak = max(abs(seg.max()), abs(seg.min()))
thr = max(6.0, 1.5 * (seg.max() - seg.min()) / 60.0)
print('滑行段幅值范围 %.0f ~ %.0f 码  (峰峰 %.0f)，去抖阈值 %.2f 码'
      % (seg.min(), seg.max(), seg.max() - seg.min(), thr))

# 去抖零交叉：必须真的越过 +thr / -thr 才算一次过零
zcs = []           # (索引, 方向 +1 上升 / -1 下降)
state = 0          # 0=未知 1=已到 +thr 2=已到 -thr
for i in range(len(seg)):
    if state != 1 and seg[i] >= thr:
        if state == 2:
            zcs.append((i, +1))
        state = 1
    elif state != 2 and seg[i] <= -thr:
        if state == 1:
            zcs.append((i, -1))
        state = 2
print('\n滑行段认到 %d 次过零：' % len(zcs))
print('%6s %8s %10s %10s %10s' % ('#', 't(ms)', '间隔(ms)', '间隔/ci', '该半周期幅值'))
prev = None
gaps = []
amps = []
for n, (i, dr) in enumerate(zcs):
    t = ts[i]
    # 该半周期（上一次过零 -> 这一次过零）的幅值
    if n == 0:
        lo, hi = 0, i
    else:
        lo, hi = zcs[n - 1][0], i
    a = seg[lo:hi + 1]
    amp = (a.max() - a.min()) if len(a) else 0
    amps.append(amp)
    if prev is None:
        print('%6d %8.2f %10s %10s %10.0f' % (n + 1, t, '-', '-', amp))
    else:
        g = t - prev
        gaps.append((t, g))
        print('%6d %8.2f %10.2f %10.3f %10.0f'
              % (n + 1, t, g, g * 1000.0 / half_elec_us, amp))
    prev = t

# 第一次过零相对触发时刻的相位（理想：触发点在某个半周期中间，无所谓）
if gaps:
    g0 = gaps[0][1]
    print('\n★ 问题① 滑行首个半电周期 = %.2f ms ；收油门前 3xci = %.2f ms ；比值 %.3f'
          % (g0, half_elec_us / 1000.0, g0 * 1000.0 / half_elec_us))
    gs = [g for _, g in gaps]
    print('   滑行各半电周期: %s ms' % ', '.join('%.2f' % g for g in gs))
    # 转速趋势：半周期越长转速越低
    if len(gs) >= 2:
        print('   首个 %.2f ms -> 末个 %.2f ms （转速降到 %.0f%%）'
              % (gs[0], gs[-1], 100.0 * gs[0] / gs[-1]))
    print('★ 问题② 幅值 %s 码' % ' -> '.join('%.0f' % a for a in amps))
    if len(amps) >= 2 and amps[0] > 0:
        print('   幅值末/首 = %.2f ；半周期末/首 = %.2f '
              % (amps[-1] / amps[0], gs[-1] / gs[0]))

# ---------- 出图 ----------
fig, ax = plt.subplots(2, 1, figsize=(14, 8.5), height_ratios=[2, 1.15], sharex=True)
ax[0].plot(t_ms, d, '-', lw=1.1, color='#2c3e50', label='delta = 悬空相 - V0')
ax[0].axvline(0, color='#c0392b', lw=1.6, ls='--', label='触发（油门归 0）')
ax[0].axvline(t_ms[start_i], color='#27ae60', lw=1.2, ls=':', label='纯滑行起点')
for n, (i, dr) in enumerate(zcs):
    ax[0].plot(ts[i], seg[i], '^' if dr > 0 else 'v', color='#8e44ad', ms=7,
               zorder=5)
    ax[0].annotate('%d' % (n + 1), (ts[i], seg[i]), textcoords='offset points',
                   xytext=(0, 10 if dr > 0 else -16), fontsize=8, color='#8e44ad')
ax[0].axhline(0, color='gray', lw=0.7, ls=':')
ax[0].set_ylabel('ADC 码')
ax[0].set_title('滑行段纯反电势：过零位置（紫）与幅值衰减  ·  过半周期应 = 3xci = %.2f ms'
                % (half_elec_us / 1000.0))
ax[0].legend(loc='upper right', fontsize=9)
ax[0].grid(alpha=0.3)

if gaps:
    gt = [t for t, _ in gaps]
    gv = [g for _, g in gaps]
    ax[1].plot(gt, gv, 'o-', color='#2980b9', label='实测半电周期')
    ax[1].axhline(half_elec_us / 1000.0, color='#c0392b', ls='--',
                  label='收油门前 3xci = %.2f ms' % (half_elec_us / 1000.0))
    ax[1].set_ylabel('半电周期 (ms)')
    ax[1].set_xlabel('距触发时刻 (ms)')
    ax[1].legend(fontsize=9)
    ax[1].grid(alpha=0.3)
    ax2 = ax[1].twinx()
    ax2.plot([t for t, _ in gaps], amps[1:] if len(amps) > len(gaps) else amps,
             's--', color='#e67e22', alpha=0.8, label='该半周期幅值')
    ax2.set_ylabel('幅值 (码)', color='#e67e22')
    ax2.tick_params(axis='y', colors='#e67e22')
    ax2.legend(fontsize=9, loc='lower left')

plt.tight_layout()
plt.savefig('/home/lpl/桌面/RM2027/coast_analyze.png', dpi=130)
print('\n图已存: /home/lpl/桌面/RM2027/coast_analyze.png')
