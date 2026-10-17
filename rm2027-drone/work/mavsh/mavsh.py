#!/usr/bin/env python3
"""通过 MAVLink 的 SERIAL_CONTROL 跟飞控的 nsh 控制台对话。
用法: mavsh.py "/dev/ttyUSB0" 57600 "cmd1" "cmd2" ...
"""
import sys, time
from pymavlink import mavutil

port = sys.argv[1]; baud = int(sys.argv[2]); cmds = sys.argv[3:]
dev = mavutil.mavlink.SERIAL_CONTROL_DEV_SHELL
FL_RESPOND = mavutil.mavlink.SERIAL_CONTROL_FLAG_RESPOND
FL_EXCLUSIVE = mavutil.mavlink.SERIAL_CONTROL_FLAG_EXCLUSIVE

m = mavutil.mavlink_connection(port, baud=baud)
print("等待心跳...", flush=True)
m.wait_heartbeat(timeout=15)
print(f"连上: sys={m.target_system} comp={m.target_component}", flush=True)

buf = ""
def pump(sec):
    global buf
    t0 = time.time()
    while time.time() - t0 < sec:
        msg = m.recv_match(type='SERIAL_CONTROL', blocking=True, timeout=0.3)
        if msg and msg.count > 0:
            buf += bytes(msg.data[:msg.count]).decode('utf-8', 'replace')

def send(s):
    payload = s.encode()[:70]
    data = list(payload) + [0]*(70-len(payload))
    m.mav.serial_control_send(0, 0, dev, FL_RESPOND | FL_EXCLUSIVE, len(payload), data)

pump(1.0)
send("\n"); pump(0.8)
for c in cmds:
    print(f"\n$ {c}", flush=True)
    buf = ""
    send(c + "\n"); pump(3.0)
    print(buf.rstrip(), flush=True)
