#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zcw-dump.py —— 读【多窗口】闭环波形捕获并画图。
用法: python3 zcw-dump.py [out.npz]

固件侧 adc_zc.c（多窗口版）：
  每样本 4 字节：delta(i16) + step(u8) + zc(u8)          共 ZCW_WIN(4) x ZCW_N(256) 个
  交棒时 arm() ⇒ 第 0 窗口【滚动】记录触发前 10.7ms
  触发（ci 涨过阈值）⇒ 记下 trig_idx、写指针跳到第 1 窗口 ⇒ 线性填满 1~3 窗 ⇒ 冻结
  ⇒ 冻结后 = 触发前 10.7ms + 触发后 32ms = 42.7ms 连续波形

★ 三条纪律（都踩过）：只在电机停转后跑；分段读+喂狗；openocd 输出在 stderr 且要字对齐。
"""
import subprocess, re, sys
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
OUT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/zcw.npz'
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
        if m: ws += [int(x, 16) for x in m.group(1).split()]
    raw = b''.join(w.to_bytes(4, 'little') for w in ws)[:nb]
    return np.frombuffer(raw, dtype=dt)

# 元数据：逐字读，按字内偏移取
w_idx  = rd_word(A('zcw_idx') & ~3)     # zcw_idx(u16) | zcw_win(u8) 
w_st   = rd_word(A('zcw_state') & ~3)   # zcw_state(u8) 附近
w_tr   = rd_word(A('zcw_trig_idx') & ~3)
w_ci   = rd_word(A('zcw_ci_trig') & ~3)
zcw_idx  = (w_idx >> 16) & 0xFFFF if (A('zcw_idx') & 2) else (w_idx & 0xFFFF)
zcw_state= (w_st >> ((A('zcw_state') & 3) * 8)) & 0xFF
trig_idx = (w_tr >> ((A('zcw_trig_idx') & 2) * 8)) & 0xFFFF   # 字内偏移：u16 落在高半字
ci_trig  = w_ci

d    = rd_arr('zcw_d', '<i2')
step = rd_arr('zcw_step', 'u1')
zc   = rd_arr('zcw_zc', 'u1')
N = 256
nwin = len(d) // N
print(f"state={zcw_state}（2=已冻结） 采样窗口数={nwin} 每窗={N}点 zcw_idx={zcw_idx} trig_idx={trig_idx} ci_trig={ci_trig}")

# 第 0 窗是滚动环 ⇒ 用 trig_idx 旋转还原（trig_idx 处 = 触发点，其后为触发后）
d0   = d[:N].copy();   s0 = step[:N].copy();   z0 = zc[:N].copy()
rot = (np.arange(N) + (trig_idx % N)) % N
d0, s0, z0 = d0[rot], s0[rot], z0[rot]
d    = np.concatenate([d0] + [d[k*N:(k+1)*N] for k in range(1, nwin)])
step = np.concatenate([s0] + [step[k*N:(k+1)*N] for k in range(1, nwin)])
zc   = np.concatenate([z0] + [zc[k*N:(k+1)*N] for k in range(1, nwin)])

FS = 1e6 / 24000.0
t = (np.arange(len(d)) - (N - trig_idx % N)) * FS / 1000.0     # 0 = 触发点
np.savez(OUT, d=d, step=step, zc=zc, trig_off=N - trig_idx % N)
print(f"已存 {OUT}（{len(d)} 点 = {len(d)*FS/1000:.1f}ms）")

ROLE = {1:('C','B','A'), 2:('A','B','C'), 3:('B','A','C'), 4:('C','A','B'), 5:('A','C','B'), 6:('B','C','A')}
fig, ax = plt.subplots(2, 1, figsize=(17, 8), sharex=True, gridspec_kw={'height_ratios': [2.2, 1]})
a = ax[0]
a.plot(t, d, 'o-', ms=2.6, lw=0.9, color='#34495e', label='delta = 悬空相 − V0（判据用的量）')
a.axhline(0, color='gray', lw=0.9, ls=':')
a.axvline(0, color='#8e0000', lw=1.8, ls='--', label='触发（ci 涨过门槛）= 交棒后不久')
zi = np.where(zc != 0)[0]
for p in zi:
    col = '#1e8449' if zc[p] == 1 else '#1f4e9c'
    a.axvline(t[p], color=col, lw=1.0, alpha=0.7)
    a.plot(t[p], d[p], '^' if zc[p] == 1 else 'v', ms=8, color=col, zorder=5)
chg = [i for i in range(1, len(d)) if step[i] != step[i-1]]
for k, c in enumerate(chg):
    if 1 <= step[c] <= 6:
        fl, lo, hi = ROLE[step[c]]
        a.text(t[c] + 0.05, 150, f"s{step[c]} 高{hi}低{lo}浮{fl}", fontsize=6, color='#7d3c98')
a.legend(fontsize=8, loc='lower left', ncol=2)
a.set_ylabel('ADC 码'); a.grid(alpha=0.25)
a.set_title(f'闭环多窗口捕获：{nwin} 窗 × {N} 点 = {len(d)*FS/1000:.1f}ms 连续波形   '
            '▲升沿 ▼降沿=代码认到的过零   紫字=代码认为该切哪两相')
a = ax[1]
a.step(t, step, where='post', color='#7d3c98', lw=1.1)
for p in zi:
    a.plot(t[p], step[p] + (0.25 if zc[p] == 1 else -0.25), '^' if zc[p] == 1 else 'v',
           ms=7, color='#1e8449' if zc[p] == 1 else '#1f4e9c')
a.axvline(0, color='#8e0000', lw=1.8, ls='--')
a.set_ylim(0.3, 6.7); a.set_ylabel('step (1..6)'); a.grid(alpha=0.25)
a.set_xlabel('距触发时刻 (ms)')
plt.tight_layout()
plt.savefig('/home/lpl/桌面/RM2027/cl_wave.png', dpi=130)
print("图已存: /home/lpl/桌面/RM2027/cl_wave.png")
