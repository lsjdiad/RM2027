#!/usr/bin/env python3
"""把 PX4 的 .ulg 日志画成曲线图。
用法:  python3 ~/RM2027/plotlog.py <日志.ulg> [输出.png]
不给路径时，自动挑 build 目录下最新的那份日志。
"""
import sys, glob, os
from pyulog import ULog
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def newest_log():
    c = glob.glob(os.path.expanduser('~/RM2027/PX4-Autopilot/build/px4_sitl_default/rootfs/fs/log/*/*.ulg'))
    if not c: c = glob.glob(os.path.expanduser('~/RM2027/PX4-Autopilot/**/*.ulg'), recursive=True)
    return max(c, key=os.path.getmtime) if c else None

log = sys.argv[1] if len(sys.argv) > 1 else newest_log()
out = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/RM2027/log_plot.png')
if not log or not os.path.exists(log):
    sys.exit('找不到 .ulg 日志，请把路径作为第一个参数传进来')
u = ULog(log)
d = {x.name: x for x in u.data_list}
t0 = None
fig, ax = plt.subplots(3, 1, figsize=(11, 9), sharex=True)

def series(topic, field):
    if topic not in d or field not in d[topic].data: return None, None
    x = d[topic].data['timestamp'] / 1e6
    return x - x[0], d[topic].data[field]

# 1) 高度（z 轴向下为正，取负 = 离地高度）
t, z = series('vehicle_local_position', 'z')
if t is not None: ax[0].plot(t, -z, lw=1); ax[0].set_ylabel('高度 (m)')
ax[0].set_title('离地高度'); ax[0].grid(alpha=.3)

# 2) 姿态：横滚/俯仰角
for topic, q, label in [('vehicle_attitude', None, None)]:
    if topic in d:
        import math
        for idx, (f, name) in enumerate([('q[1]', '横滚 roll'), ('q[2]', '俯仰 pitch')]):
            if f in d[topic].data:
                x = d[topic].data['timestamp']/1e6; x = x - x[0]
                val = [2*math.asin(max(-1, min(1, v)))*57.2958 for v in d[topic].data[f]]
                ax[1].plot(x, val, lw=1, label=name)
ax[1].set_ylabel('角度 (度)'); ax[1].set_title('姿态角（粗略换算）'); ax[1].legend(); ax[1].grid(alpha=.3)

# 3) 四个电机输出
for topic in ('actuator_motors', 'actuator_outputs'):
    if topic in d:
        ks = sorted([k for k in d[topic].data if k.startswith(('control[', 'output['))])[:4]
        x = d[topic].data['timestamp']/1e6; x = x - x[0]
        for k in ks: ax[2].plot(x, d[topic].data[k], lw=1, label=k)
        ax[2].set_title(f'电机输出（{topic}）'); break
ax[2].set_xlabel('时间 (秒)'); ax[2].set_ylabel('输出'); ax[2].legend(); ax[2].grid(alpha=.3)

plt.tight_layout(); plt.savefig(out, dpi=110)
print('图已保存:', out)
print('日志:', log)
