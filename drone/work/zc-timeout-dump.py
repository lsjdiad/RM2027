#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zc-timeout-dump.py —— 读"卡顿现场"：每次【超时硬踹】时的占空比 / 电流 / 等了多久。
用法: python3 zc-timeout-dump.py

固件侧（main.c 闭环超时兜底分支，强制换相之前）记录最近 64 次：
  tm_duty[] duty_cycle（0..2000）  tm_cur[] actual_current   tm_cnt[] INTERVAL_TIMER_COUNT
  tm_idx = 已记录条数   tm_total = 累计卡顿次数

★ 关键判读（区分两种完全相反的病因）：
  RM2027_BENCH_OC_LIMIT = 110 ≈ 实际 1.8A ，正常运行电流中位约 25~30
  · 卡顿时电流【大】（接近 110）⇒ 线圈在使劲而转子不动 = 真堵转
    ⇒ 低惯量 / 齿槽假说成立
  · 卡顿时电流【小】（≈25）⇒ 驱动其实被切掉了 = 换相逻辑问题
    ⇒ 与惯量无关
  tm_cnt 是"卡了多久才被硬踹"，1 拍 = 0.5us。
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

def rd_u8(name):
    w = rd_word(A(name) & ~3)
    return (w >> ((A(name) & 3) * 8)) & 0xFF

def rd_u32(name):
    return rd_word(A(name))

idx = rd_u8('tm_idx')
total = rd_u32('tm_total')
duty = rd_arr('tm_duty', '<u2').astype(int)
cur  = rd_arr('tm_cur', '<i2').astype(int)
cnt  = rd_arr('tm_cnt', '<u2').astype(int)
n = min(idx, len(duty))

print('累计卡顿（超时硬踹）次数 = %d ；本次记录 %d 条' % (total, n))
if n == 0:
    raise SystemExit('没有卡顿记录 —— 说明这一轮闭环没有出现超时硬踹')

print('\n%4s %8s %8s %12s %10s' % ('#', 'duty', 'cur', '等了(ms)', 'cur 判读'))
for i in range(n):
    tag = '★大电流(堵转?)' if cur[i] > 70 else (' 小电流(驱动缺失?)' if cur[i] < 40 else ' 中间')
    print('%4d %8d %8d %12.2f %10s' % (i, duty[i], cur[i], cnt[i]*0.5/1000.0, tag))

d = np.array([duty[i] for i in range(n)])
c = np.array([cur[i] for i in range(n)])
k = np.array([cnt[i] for i in range(n)])
print('\n统计：duty 中位 %d (%.1f%%)   cur 中位 %d  最大 %d   等时中位 %.2f ms  最大 %.2f ms'
      % (np.median(d), np.median(d)*100/2000, np.median(c), c.max(),
         np.median(k)*0.5/1000, k.max()*0.5/1000))
print('对照：正常运行电流中位约 25~30 ；RM2027_BENCH_OC_LIMIT = 110 (约 1.8A)')
big = int((c > 70).sum())
print('\n★ 结论倾向：%d/%d 次卡顿是大电流（>70）' % (big, n))
if big * 2 > n:
    print('  ⇒ 线圈在使劲而转子不动 = 真堵转 ⇒【低惯量/齿槽假说成立】')
else:
    print('  ⇒ 卡顿时电流并不大 ⇒ 驱动被切掉了 = 换相逻辑问题，与惯量无关')
