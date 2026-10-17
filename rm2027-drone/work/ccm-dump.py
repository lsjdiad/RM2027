#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ccm-dump.py —— 读固件的【闭环换相历史】并画图。
用法: python3 ccm-dump.py

固件侧（Src/main.c 的 ccm_record()，在离群值钳制【之前】调用）：
  细记录 ccm_ci[1024]  = 【未钳制的原始实测步长】(0.5us/tick)
                         —— 不是 commutation_interval（那是六步平均 + 钳制过的）
  细记录 ccm_step[1024]= step
  粗时间线 ccm_slow_*[128]（每 64 次换相一笔）：
      ci   平滑后的 commutation_interval（与原始值对比 ⇒ 钳制抹掉了多少）
      duty duty_cycle / cur actual_current / iov input_override
      in   input（速度环输出 = iov/10000）/ sp duty_cycle_setpoint（各上限截断前）

要回答：用户肉眼看到的"开环稳且快、闭环抖且慢"到底抖多少、慢多少。
  ⇒ 开环的换相间隔由固定时基给出，严格相等（抖≈0）；
     闭环靠每次过零决定换相时刻 ⇒ 抖动量直接体现在第一张图上。
"""
import subprocess, re
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

ELF = '/home/lpl/桌面/RM2027/AM32-rm2027/obj/AM32_RM2027_ESC_G071_2.21.elf'
NM, W, BC = '/usr/bin/arm-none-eabi-nm', 128, 128 * 4

syms = {}
for l in subprocess.run([NM, '-S', ELF], capture_output=True, text=True).stdout.splitlines():
    f = l.split()
    if len(f) == 4:
        syms[f[3]] = (int(f[0], 16), int(f[1], 16))
A = lambda n: syms[n][0]
SZ = lambda n: syms[n][1]

def oc(args):
    r = subprocess.run(['openocd', '-f', 'interface/stlink.cfg', '-f', 'target/stm32g0x.cfg',
                        '-c', 'adapter speed 1800', '-c', 'init', *args, '-c', 'shutdown'],
                       capture_output=True, text=True)
    return r.stdout + r.stderr

def rd_word(addr):
    out = oc(['-c', 'halt', '-c', 'mww 0x40003000 0xAAAA', '-c', f'mdw {addr:#x} 1',
              '-c', 'mww 0x40003000 0xAAAA', '-c', 'resume'])
    m = re.search(r'^0x[0-9a-fA-F]+:\s*([0-9a-fA-F]+)', out, re.M)
    return int(m.group(1), 16) if m else None

def rd_arr(name, dt):
    n = SZ(name) // np.dtype(dt).itemsize
    nb = n * np.dtype(dt).itemsize
    args = ['-c', 'halt', '-c', 'mww 0x40003000 0xAAAA']
    for c in range((nb + BC - 1) // BC):
        args += ['-c', f'mdw {A(name) + c*BC:#x} {W}', '-c', 'mww 0x40003000 0xAAAA']
    args += ['-c', 'resume']
    ws = []
    for l in oc(args).splitlines():
        m = re.match(r'^0x[0-9a-fA-F]+:\s*(.*)$', l)
        if m:
            ws += [int(x, 16) for x in m.group(1).split()]
    raw = b''.join(w.to_bytes(4, 'little') for w in ws)[:nb]
    return np.frombuffer(raw, dtype=dt)

def rd_u16(name):
    w = rd_word(A(name) & ~3)
    return (w >> ((A(name) & 2) * 8)) & 0xFFFF

def rd_u32(name):
    return rd_word(A(name))

NA = 1024
raw  = rd_arr('ccm_ci', '<u2').astype(np.int64)      # 原始实测步长（未钳制）
st   = rd_arr('ccm_step', 'u1').astype(np.int64)
head, total = rd_u16('ccm_head'), rd_u32('ccm_total')
NS = 128
sci  = rd_arr('ccm_slow_ci', '<u2').astype(np.int64)
sdut = rd_arr('ccm_slow_duty', '<u2').astype(np.int64)
scur = rd_arr('ccm_slow_cur', '<i2').astype(np.int64)
siov = rd_arr('ccm_slow_iov', '<u4').astype(np.int64)
sin_ = rd_arr('ccm_slow_in', '<u2').astype(np.int64)
ssp  = rd_arr('ccm_slow_sp', '<u2').astype(np.int64)
shead, stotal = rd_u16('ccm_slow_head'), rd_u32('ccm_slow_total')

n = min(total, NA)
if n == 0:
    raise SystemExit('一笔都没记到 —— 这次没有进入闭环换相')
order = np.arange(n) if total <= NA else (np.arange(n) + head) % NA
raw, st = raw[order], st[order]
ms = raw * (1000.0 / 24000.0)   # 帧 -> ms（1 帧 = 41.67us）
med = np.median(ms)
sd = ms.std()
zero = int((raw == 0).sum())
nz = ms[raw > 0]
print('细记录（真实换相间隔 = ADC 帧数 x 41.67us）：%d 笔（累计 %d）' % (n, total))
print('  间隔为 0 的步（连续两帧就换相，异常）：%d / %d' % (zero, n))
if len(nz):
    print('  有过零的步：中位 %.3f  均值 %.3f  最小 %.3f  最大 %.3f ms  标准差 %.3f ms = 中位的 %.1f%%'
          % (np.median(nz), nz.mean(), nz.min(), nz.max(), nz.std(), nz.std()/np.median(nz)*100))
print('  中位 %.3f ms   均值 %.3f ms   最小 %.3f   最大 %.3f ms'
      % (med, ms.mean(), ms.min(), ms.max()))
print('  ★ 抖动：标准差 %.3f ms = 中位的 %.1f%%   （开环由固定时基给间隔 ⇒ 抖≈0）'
      % (sd, sd/med*100))
for k in (1.2, 1.5, 2.0, 3.0):
    c = int((ms > k*med).sum())
    print('    步长 > %.1fx中位 的步数：%d / %d （%.1f%%）' % (k, c, n, c*100.0/n))
print('  ★ 等效平均转速：%.0f 转/分（6 极对）   vs 开环目标 1670'
      % (60.0/(ms.mean()*6/1000.0)/6))
print('\n★ 按 step 分组（看哪一步系统性偏长 —— 若某步固定偏长，说明那个相的过零/换相有问题）：')
for _s in range(1, 7):
    m = (st == _s)
    if m.sum():
        print('   step %d: n=%3d  中位 %.3f ms  均值 %.3f ms  最大 %.3f ms'
              % (_s, m.sum(), np.median(ms[m]), ms[m].mean(), ms[m].max()))

# ★ 稳态统计：去掉首尾各 15%（避开起步交棒段与收油门段）
_a, _b = int(n*0.15), int(n*0.85)
_ss = ms[_a:_b]
print('\n★★ 稳态段（掐掉首尾各 15%%，共 %d 笔）：中位 %.3f ms  均值 %.3f ms  标准差 %.3f ms  最大 %.3f ms'
      % (len(_ss), np.median(_ss), _ss.mean(), _ss.std(), _ss.max()))
print('   ⇒ 稳态等效转速 %.0f 转/分（开环 1670）' % (60.0/(_ss.mean()*6/1000.0)/6))
_l = np.where(ms > 2*np.median(ms))[0]
if len(_l):
    print('   长步(>2x中位) 共 %d 个；其中落在首 15%% 段 %d 个、末 15%% 段 %d 个、稳态段 %d 个'
          % (len(_l), (_l < _a).sum(), (_l >= _b).sum(), ((_l >= _a) & (_l < _b)).sum()))
    _sl = _l[(_l >= _a) & (_l < _b)]
    if len(_sl) > 2:
        _d = np.diff(_sl)
        print('   稳态长步的序号间隔(步)：%s' % ' '.join(str(x) for x in _d[:24]))
        print('   （若间隔集中在某个数附近 ⇒ 周期性 = 与机械/电气旋转位置相关；'
              '若很散 ⇒ 随机事件）')

bad = sum(1 for i in range(1, n) if st[i] != (st[i-1] % 6) + 1)
print('  step 非"每步+1"：%d 处（正常 0）' % bad)

ns = min(stotal, NS)
sord = np.arange(ns) if stotal <= NS else (np.arange(ns) + shead) % NS
sci_, sdut_, scur_, siov_ = sci[sord], sdut[sord], scur[sord], siov[sord]
sin2, ssp2 = sin_[sord], ssp[sord]
tsc = np.cumsum(sci_) * 64 * 0.5 / 1e6
tsc = tsc - tsc[-1]

print('\n粗时间线：%d 点 x 64 次换相，覆盖约 %.1f 秒' % (ns, 64*np.sum(sci_)*0.5/1e6))
print('  占空比 duty：中位 %d (%.1f%%)  最大 %d (%.1f%%)   （开环对照 340 = 17.0%%）'
      % (np.median(sdut_), np.median(sdut_)*100/2000, sdut_.max(), sdut_.max()*100/2000))
print('  电流 cur：中位 %d  最大 %d' % (np.median(scur_), scur_.max()))
print('  ★ 电调内部认为的步长(平滑 ci)：中位 %.3f ms  首 %.3f  末 %.3f  最大 %.3f'
      % (np.median(sci_)*0.5/1000, sci_[0]*0.5/1000, sci_[-1]*0.5/1000, sci_.max()*0.5/1000))
print('  input：首 %d 末 %d 最大 %d  ；duty_cycle_setpoint：首 %d 末 %d 最大 %d'
      % (sin2[0], sin2[-1], sin2.max(), ssp2[0], ssp2[-1], ssp2.max()))
print('  input_override：首 %d 末 %d 最大 %d（上限 20470000）'
      % (siov[0], siov[-1], siov.max()))

fig, ax = plt.subplots(3, 1, figsize=(15, 11))
ax[0].plot(np.arange(n), ms, '-', lw=0.8, color='#c0392b')
ax[0].axhline(med, color='gray', ls='--', lw=0.9, label='中位 %.3f ms' % med)
ax[0].set_ylabel('真实换相间隔 (ms)')
ax[0].set_xlabel('第 n 次换相（最近 %d 笔）' % n)
ax[0].set_title('★ 闭环换相间隔的真实分布（ADC 帧时间戳，不依赖过零检测）  标准差 %.3f ms'
                % (sd, sd/med*100))
ax[0].legend(fontsize=9); ax[0].grid(alpha=0.3)

ax[1].plot(tsc, sci_*0.5/1000.0, 'o-', ms=3.5, lw=1.1, color='#c0392b', label='平滑后 ci')
ax[1].plot(tsc, sdut_*100/2000.0, 's-', ms=3, lw=1.0, color='#2980b9', label='占空比 (%)')
ax[1].axhline(17.0, color='#27ae60', ls='--', lw=1.0, label='开环占空比 17%')
ax[1].set_ylabel('ci (ms) / 占空比 (%)'); ax[1].legend(fontsize=9); ax[1].grid(alpha=0.3)
ax1b = ax[1].twinx()
ax1b.plot(tsc, scur_, '^--', ms=3, lw=0.9, color='#e67e22', alpha=0.85, label='电流 cur')
ax1b.set_ylabel('电流 cur', color='#e67e22'); ax1b.tick_params(axis='y', colors='#e67e22')
ax1b.legend(fontsize=9, loc='upper right')

ax[2].plot(tsc, sin2, 'o-', ms=3.5, lw=1.1, color='#16a085', label='input（速度环输出）')
ax[2].plot(tsc, ssp2, 's-', ms=3, lw=1.0, color='#8e44ad', label='duty_cycle_setpoint')
ax[2].set_ylabel('刻度 (0..2047)'); ax[2].legend(fontsize=9); ax[2].grid(alpha=0.3)
ax[2].set_xlabel('时间 (s)，0 = 最后一笔')
plt.tight_layout()
plt.savefig('/home/lpl/桌面/RM2027/ccm_hist_v2.png', dpi=130)
print('\n图已存: /home/lpl/桌面/RM2027/ccm_hist.png')
