#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 PX4 飞行日志里的"速度被拉回 0"过程画出来。

用法（不给参数就自动挑最新日志）：
    python3 ~/RM2027/plot_vel.py
    python3 ~/RM2027/plot_vel.py <某个.ulg>

输出两张图：
    ~/RM2027/flight_overview.png   整个飞行段的概览
    ~/RM2027/flight_zoom.png       自动放大到水平速度最快的那一段

脚本会自动找出"解锁到上锁"的时间段，所以换一份日志也能直接用。
"""
import glob
import os
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from pyulog import ULog

plt.rcParams['font.sans-serif'] = ['Noto Sans CJK SC']
plt.rcParams['axes.unicode_minus'] = False

RAD2DEG = 57.2957795
HOME = os.path.expanduser('~')


def newest_log():
    pat = os.path.join(HOME, 'RM2027/PX4-Autopilot/build/px4_sitl_default/rootfs/fs/log/*/*.ulg')
    c = glob.glob(pat) or glob.glob(os.path.join(HOME, 'RM2027/PX4-Autopilot/**/*.ulg'), recursive=True)
    return max(c, key=os.path.getmtime) if c else None


def pick_flight_window(u, T0):
    """返回 (起点, 终点)：优先用"解锁到上锁"的区间，找不到就整份日志。"""
    if any(d.name == 'actuator_armed' for d in u.data_list):
        d = u.get_dataset('actuator_armed')
        t = d.data['timestamp'] / 1e6 - T0
        armed = np.asarray(d.data['armed']).astype(bool)
        if armed.any():
            idx = np.where(armed)[0]
            return float(t[idx[0]]), float(t[idx[-1]])
    t = u.get_dataset('vehicle_local_position').data['timestamp'] / 1e6 - T0
    return float(t[0]), float(t[-1])


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else newest_log()
    if not log or not os.path.exists(log):
        sys.exit('找不到 .ulg 日志，把路径作为第一个参数传进来')

    print(f'日志: {log}')
    u = ULog(log)
    T0 = u.start_timestamp / 1e6      # 所有 topic 共用这个时间基准

    cache = {}

    def get(topic, field, multi=0):
        key = (topic, multi)
        if key not in cache:
            d = u.get_dataset(topic, multi)
            t = d.data['timestamp'] / 1e6 - T0
            cache[key] = (t, d.data)
        t, data = cache[key]
        return (t, data[field]) if field is not None else (t, data)

    t, z = get('vehicle_local_position', 'z')
    _, vx = get('vehicle_local_position', 'vx')
    _, vy = get('vehicle_local_position', 'vy')
    spd = np.hypot(vx, vy)
    alt = -z

    t_sp, roll_sp = get('vehicle_rates_setpoint', 'roll')
    _, pitch_sp = get('vehicle_rates_setpoint', 'pitch')
    t_w, wx = get('vehicle_angular_velocity', 'xyz[0]')
    _, wy = get('vehicle_angular_velocity', 'xyz[1]')

    t_m, md = get('actuator_motors', None)
    ctrl = [md[f'control[{i}]'] for i in range(4)]

    t0, t1 = pick_flight_window(u, T0)
    m = (t >= t0) & (t <= t1)
    print(f'飞行段: {t0:.1f}s -> {t1:.1f}s  (时长 {t1 - t0:.1f}s)')
    print(f'  最大水平速度 {spd[m].max():.2f} m/s, 最高 {alt[m].max():.2f} m')

    # ---------------- 图 1：总览 ----------------
    fig, ax = plt.subplots(4, 1, sharex=True, figsize=(13, 11))

    ax[0].plot(t[m], alt[m], lw=1, color='tab:blue')
    ax[0].set_ylabel('高度 (m)')
    ax[0].set_title('高度')
    ax[0].grid(alpha=.3)

    ax[1].plot(t[m], vx[m], lw=1, label='vx 北/前')
    ax[1].plot(t[m], vy[m], lw=1, label='vy 东/右')
    ax[1].plot(t[m], spd[m], lw=1.6, color='k', label='水平速度大小', alpha=.6)
    ax[1].set_ylabel('速度 (m/s)')
    ax[1].set_title('水平速度 —— 外环就是在把这两个拉回 0')
    ax[1].legend(loc='upper right', ncol=3, fontsize=9)
    ax[1].grid(alpha=.3)

    ax[2].plot(t_sp, roll_sp * RAD2DEG, lw=1, label='roll 期望')
    mm = (t_w >= t0) & (t_w <= t1)
    ax[2].plot(t_w[mm], wx[mm] * RAD2DEG, lw=1, label='roll 实际', alpha=.8)
    ax[2].set_ylabel('角速率 (deg/s)')
    ax[2].set_title('横滚角速率：期望 vs 实际（两条贴合 = 内环没问题）')
    ax[2].legend(loc='upper right', fontsize=9)
    ax[2].grid(alpha=.3)

    for i, c in enumerate(ctrl):
        mm2 = (t_m >= t0) & (t_m <= t1)
        ax[3].plot(t_m[mm2], c[mm2], lw=1, label=f'电机 {i + 1}')
    ax[3].set_ylabel('输出 (0~1)')
    ax[3].set_xlabel('时间 (s，相对日志起点)')
    ax[3].set_title('电机输出')
    ax[3].legend(loc='upper right', ncol=4, fontsize=9)
    ax[3].grid(alpha=.3)

    ax[0].set_xlim(t0, t1)
    plt.tight_layout()
    out1 = os.path.join(HOME, 'RM2027/flight_overview.png')
    plt.savefig(out1, dpi=110)
    plt.close(fig)
    print(f'  图 1 已保存: {out1}')

    # ---------------- 图 2：放大到速度最快的一段 ----------------
    peak_i = np.argmax(np.where(m, spd, 0))
    center = t[peak_i]
    a, b = center - 8, center + 14
    print(f'放大区段: {a:.0f}s -> {b:.0f}s（水平速度峰值 {spd[peak_i]:.2f} m/s 在 {center:.1f}s）')

    fig, ax = plt.subplots(4, 1, sharex=True, figsize=(13, 11))

    mm = (t >= a) & (t <= b)
    ax[0].plot(t[mm], vx[mm], lw=1.4, label='vx 北/前')
    ax[0].plot(t[mm], vy[mm], lw=1.4, label='vy 东/右')
    ax[0].axhline(0, color='k', lw=.8, alpha=.4)
    ax[0].set_ylabel('速度 (m/s)')
    ax[0].set_title(f'水平速度放大（{a:.0f}–{b:.0f}s）：看穿越 0 之后是收敛还是来回摆')
    ax[0].legend(loc='upper right', fontsize=9)
    ax[0].grid(alpha=.3)

    mm_sp = (t_sp >= a) & (t_sp <= b)
    mm_w = (t_w >= a) & (t_w <= b)
    ax[1].plot(t_sp[mm_sp], roll_sp[mm_sp] * RAD2DEG, lw=1.4, label='期望')
    ax[1].plot(t_w[mm_w], wx[mm_w] * RAD2DEG, lw=1.2, label='实际', alpha=.85)
    ax[1].set_ylabel('横滚角速率 (deg/s)')
    ax[1].set_title('横滚角速率：期望 vs 实际')
    ax[1].legend(loc='upper right', fontsize=9)
    ax[1].grid(alpha=.3)

    ax[2].plot(t_sp[mm_sp], pitch_sp[mm_sp] * RAD2DEG, lw=1.4, label='期望')
    ax[2].plot(t_w[mm_w], wy[mm_w] * RAD2DEG, lw=1.2, label='实际', alpha=.85)
    ax[2].set_ylabel('俯仰角速率 (deg/s)')
    ax[2].set_title('俯仰角速率：期望 vs 实际')
    ax[2].legend(loc='upper right', fontsize=9)
    ax[2].grid(alpha=.3)

    mm_m = (t_m >= a) & (t_m <= b)
    for i, c in enumerate(ctrl):
        ax[3].plot(t_m[mm_m], c[mm_m], lw=1.2, label=f'电机 {i + 1}')
    ax[3].set_ylabel('输出 (0~1)')
    ax[3].set_xlabel('时间 (s，相对日志起点)')
    ax[3].set_title('电机输出：平滑说明控制没在抖；高频毛刺才是控制振荡')
    ax[3].legend(loc='upper right', ncol=4, fontsize=9)
    ax[3].grid(alpha=.3)

    ax[0].set_xlim(a, b)
    plt.tight_layout()
    out2 = os.path.join(HOME, 'RM2027/flight_zoom.png')
    plt.savefig(out2, dpi=110)
    plt.close(fig)
    print(f'  图 2 已保存: {out2}')


if __name__ == '__main__':
    main()
