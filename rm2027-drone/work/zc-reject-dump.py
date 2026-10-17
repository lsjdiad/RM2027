#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zc-reject-dump.py —— 读过零判据的【被拒收现场】，判断该放宽哪一条。
用法: python3 zc-reject-dump.py

固件侧（adc_zc.c）：最近 32 次拒收各存
  8 个原始样本（snap[i][0]=最新 …… snap[i][7]=最老，单位 ADC 码）
  code：1 = 上升沿被"严格单调"关掉、2 = 下降沿被关掉、3 = 斜率上限关掉
  cnt ：拒收时的 INTERVAL_TIMER 读数（该定时器每次换相清零）
        ⇒ cnt/ci = 拒收发生在【步内的位置】：≈0.5 才是真过零，
          很小（<0.2）是换相刚过的跳变。

判读：
  · 若拒收点 cnt/ci ≈ 0.5 且样本【基本单调、只差一点点】
    ⇒ 判据的"严格单调"太苛刻（过零附近噪声大）⇒ 给单调判据加容差
  · 若拒收点 cnt/ci 很小且样本是【大幅反向跳变】
    ⇒ 那是换相跳变，判据是对的，问题在别处
"""
import subprocess, re
import numpy as np

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

ci = rd_word(A('commutation_interval'))          # 平滑 ci（0.5us/tick）
snap = rd_arr('adc_zc_rj_snap', '<i2').reshape(-1, 8).astype(int)
code = rd_arr('adc_zc_rj_code', 'u1').astype(int)
cnt  = rd_arr('adc_zc_rj_cnt', '<u2').astype(int)
idx, total = rd_u16('adc_zc_rj_idx'), rd_u32('adc_zc_rj_total')

print('当前 commutation_interval(平滑) = %d tick = %.3f ms' % (ci, ci*0.5/1000))
print('拒收总次数 = %d ；现场缓冲 32 条，写指针 %d（0/1 = 未满/满）\n' % (total, idx))
KIND = {1: '上升被"严格单调"关掉', 2: '下降被"严格单调"关掉', 3: '斜率上限关掉'}
print('%3s %-22s %8s %8s  %s' % ('#', '原因', 'CNT', 'CNT/ci', '8 个样本（最老 -> 最新）'))
for i in range(len(code)):
    if code[i] == 0 and cnt[i] == 0 and not snap[i].any():
        continue
    s8 = snap[i][::-1]        # 反成"最老 -> 最新"
    # 相邻对是否单调
    d = [s8[j+1] - s8[j] for j in range(7)]
    ups = sum(1 for x in d if x > 0)
    dns = sum(1 for x in d if x < 0)
    if ups == 7 or dns == 7:
        mono = '严格单调'
    elif ups >= 6 or dns >= 6:
        mono = '基本单调(仅1处反向)'
    else:
        mono = '非单调(%d处反向)' % (7 - max(ups, dns))
    print('%3d %-22s %8d %8.3f  %s   %s'
          % (i, KIND.get(code[i], '?'), cnt[i], cnt[i]/ci if ci else 0,
             ' '.join('%5d' % v for v in s8), mono))

bad = [(i, cnt[i]/ci if ci else 0) for i in range(len(code)) if code[i] != 0]
if bad:
    r = np.array([b[1] for b in bad])
    print('\n拒收点 CNT/ci 统计：中位 %.2f  最小 %.2f  最大 %.2f' % (np.median(r), r.min(), r.max()))
    print('  （≈0.5 = 真过零位置；<0.2 = 换相刚过的跳变）')
    near = int((r > 0.35).sum())
    print('  其中落在"真过零附近"(>0.35)的：%d / %d' % (near, len(r)))
