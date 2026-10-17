#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解析最新的 PX4 ulog：起飞高度/飞行时长/模式变化"""
import glob, sys
sys.stdout.reconfigure(encoding='utf-8')
from pyulog import ULog

files = sorted(glob.glob('/home/drone/PX4-Autopilot/build/px4_sitl_default/rootfs/log/2026-08-30/*.ulg'))
if not files:
    print('无日志文件')
    sys.exit(0)
f = files[-1]
print('日志:', f.split('/')[-1])
u = ULog(f)
dur = u.last_timestamp / 1e6
print(f'时长: {dur:.0f}s')

# 本地位置（z 向下为正，起飞后 z 为负）
for d in u.data_list:
    if d.name == 'vehicle_local_position' and 'z' in d.data:
        zs = d.data['z']
        print(f'最大高度: {abs(min(zs)):.1f} m (z_min={min(zs):.1f})')
        break

# 起降状态
for d in u.data_list:
    if d.name == 'vehicle_status':
        keys = d.data.keys()
        if 'arming_state' in keys:
            arming = d.data['arming_state']
            print(f'解锁状态变化次数: {len(set(arming))}, 最终状态码: {int(arming[-1])} (2=armed)')
        if 'nav_state' in keys:
            nav = d.data['nav_state']
            states = {}
            for v in nav:
                states[int(v)] = states.get(int(v), 0) + 1
            print(f'飞行模式分布: {states} (4=OFFBOARD? 3=ALTCTL 2=POSCTL 13=TAKEOFF 15=AUTO_LAND)')
        break
