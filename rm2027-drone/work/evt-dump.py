#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
evt-dump.py —— 从串口接收电调的【换相事件流】，存 CSV 并画图。
用法: python3 evt-dump.py [串口] [秒数]

为什么用它（而不是 SWD 读内存）：
  芯片只有 16KB RAM，内存记录只能存 1 秒多，看不到"跑久了会不会变慢"。
  串口发"每次换相一个事件"（约 10KB/s），可以连续记录几十秒到几分钟。

帧格式（固件侧按此打包，小端）：
  A5 5A A5 5A | seq u16 | ts u32 | delta i16 | step u8 | wait u16 | duty u16 | cur i16 | flag u8 | crc8
  = 21 字节
    seq   : 事件序号（丢帧能看出来）
    ts    : 换相时刻的帧计数（24kHz，41.67us/格）—— 真实时间轴
    delta : 换相那一刻的"悬空相 − V0"（ADC 码）
    step  : 1..6
    wait  : 该步的 waitTime（换相后要等的 30 度延迟，0.5us/拍）
    duty  : 占空比（0..2000，2000 = 100%）
    cur   : 电流（电调内部单位；110 约等于 1.8A）
    crc8  : 前 19 字节的 CRC8（多项式 0x07）
"""
import sys, os, glob, struct, time
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

PORT = sys.argv[1] if len(sys.argv) > 1 else None
SECS = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
BAUD = 1000000
FRAME = 21

if PORT is None:
    cands = sorted(glob.glob('/dev/ttyUSB*')) + sorted(glob.glob('/dev/ttyACM*'))
    if not cands:
        print("❌ 没找到串口"); sys.exit(1)
    PORT = cands[0]

import serial
ser = serial.Serial(PORT, BAUD, timeout=1.0)
ser.reset_input_buffer()
print(f"串口 {PORT} @ {BAUD}，收 {SECS} 秒 ...")

buf = bytearray()
rows = []
t0 = time.time()
while time.time() - t0 < SECS:
    chunk = ser.read(4096)
    if chunk:
        buf += chunk
    while True:
        i = buf.find(b'\xA5\x5A\xA5\x5A')
        if i < 0:
            if len(buf) > 1:
                del buf[:-1]
            break
        if len(buf) - i < FRAME:
            del buf[:i]
            break
        f = bytes(buf[i:i+FRAME])
        crc = 0
        for b in f[:20]:
            crc ^= b
            for _ in range(8):
                crc = ((crc << 1) ^ 0x07) & 0xFF if (crc & 0x80) else ((crc << 1) & 0xFF)
        if crc != f[20]:
            del buf[:i+1]
            continue
        seq, ts, delta, step, wait, dut, cur, flag = struct.unpack_from('<HIhBHHhB', f, 4)
        rows.append((seq, ts, delta, step, wait, dut, cur, flag))
        del buf[:i+FRAME]
ser.close()

if not rows:
    print("❌ 没收到事件 —— 检查：① 波特率 1 Mbaud ② 接线 RX 对 PB6 ③ 电机是否在转")
    sys.exit(1)

a = np.array(rows, dtype=np.int64)
seq, ts, delta, step, wait, dut, cur, flag = (a[:, i] for i in range(8))
print(f"收到 {len(a)} 个事件")

# 时间轴：帧计数 24kHz -> 秒；用差分算间隔（处理 u32 回绕与重排序）
dseq = np.diff(seq)
gaps = np.where(dseq != 1)[0]
print(f"序号不连续的位置：{len(gaps)} 处（丢包/乱序）")

# 真实换相间隔（用时间戳差）
dts = np.diff(ts) * (1.0 / 24000.0) * 1000.0     # ms
dts[dts < 0] += (2**32) / 24000.0 * 1000.0       # 回绕
keep = np.where((dseq == 1) & (dts > 0) & (dts < 1000))[0]
iv = dts[keep]

print(f"\n换相间隔：中位 {np.median(iv):.3f} ms  均值 {iv.mean():.3f} ms  "
      f"最小 {iv.min():.3f}  最大 {iv.max():.3f}  标准差 {iv.std():.3f} ms")
print(f"  >1.2x中位：{(iv > 1.2*np.median(iv)).sum()} / {len(iv)} 个")
print(f"等效平均转速 {60.0/(iv.mean()*6/1000.0)/6:.0f} 转/分（6 极对）")
print(f"占空比 中位 {np.median(dut):.0f}/2000 = {np.median(dut)*100/2000:.1f}%  最大 {dut.max()*100/2000:.1f}%")
print(f"电流   中位 {np.median(cur):.0f}  最大 {cur.max()}")

CSV = f'/home/lpl/桌面/RM2027/evt_{time.strftime("%Y%m%d_%H%M%S")}.csv'
np.savetxt(CSV, a, delimiter=',',
           header='seq,ts_frame,delta,step,wait,duty,cur,flag_openloop', comments='', fmt='%d')
print(f"\nCSV 已存: {CSV}")

tsec = (ts - ts[0]) / 24000.0
fig, ax = plt.subplots(3, 1, figsize=(15, 9), sharex=True)
ax[0].plot(tsec[1:], iv, '-', lw=0.7, color='#c0392b')
ax[0].axhline(np.median(iv), color='gray', ls='--', lw=0.8, label='中位 %.3f ms' % np.median(iv))
ax[0].set_ylabel('换相间隔 (ms)'); ax[0].legend(fontsize=9); ax[0].grid(alpha=0.3)
ax[0].set_title('串口换相事件流：%d 个事件，%.1f 秒（可连续记录，不受 16KB RAM 限制）'
                % (len(a), tsec[-1]))
ax[1].plot(tsec, dut*100/2000.0, '-', lw=0.7, color='#2980b9', label='占空比 (%)')
ax[1].axhline(17.0, color='#27ae60', ls='--', lw=1.0, label='开环占空比 17%')
ax[1].set_ylabel('占空比 (%)'); ax[1].legend(fontsize=9); ax[1].grid(alpha=0.3)
ax1b = ax[1].twinx()
ax1b.plot(tsec, cur, '-', lw=0.6, color='#e67e22', alpha=0.7, label='电流')
ax1b.set_ylabel('电流', color='#e67e22'); ax1b.tick_params(axis='y', colors='#e67e22')
ax[2].plot(tsec, delta, '-', lw=0.6, color='#8e44ad', label='换相时刻的 delta')
ax[2].set_ylabel('delta (ADC 码)'); ax[2].legend(fontsize=9); ax[2].grid(alpha=0.3)
ax[2].set_xlabel('时间 (s)')
plt.tight_layout()
PNG = CSV.replace('.csv', '.png')
plt.savefig(PNG, dpi=130)
print(f"图已存: {PNG}")
