#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""通过 MAVLink 连接 PX4 SITL，修改起飞高度参数 MIS_TAKEOFF_ALT"""
import sys, time
sys.stdout.reconfigure(encoding='utf-8')
from pymavlink import mavutil

# 连 SITL 的 MAVLink 端口（PX4 发心跳到 14550，客户端连它）
master = mavutil.mavlink_connection('udp:127.0.0.1:14550')
print('等待 PX4 连接...')
# 等心跳
for _ in range(30):
    msg = master.recv_match(type='HEARTBEAT', timeout=1)
    if msg:
        print('已连上 PX4, 系统ID:', msg.get_srcSystem())
        break
else:
    print('超时未收到心跳（SITL 没跑或端口不通）')
    sys.exit(1)

# 读当前值
master.param_fetch_all()
time.sleep(0.5)
cur = master.mav.param_value  # 不完善，改用自己的方式
# 用 param_set 设置
PARAM = 'MIS_TAKEOFF_ALT'
VAL = 8.0
master.param_set_send(PARAM.encode(), int(VAL*100), mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
print(f'已发送设置 {PARAM}={VAL}')
time.sleep(1)

# 确认（读取当前值）
master.mav.param_request_read_send(master.target_system, master.target_component, PARAM.encode(), -1)
time.sleep(1)
r = master.recv_match(type='PARAM_VALUE', timeout=2)
if r:
    print(f'确认当前值: {r.param_id} = {r.param_value}')
else:
    print('未能收到确认（可能 SITL 仅单向广播，改值仍可能生效）')
