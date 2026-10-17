#!/usr/bin/env python3
"""MAVLink shell（带 keep-alive）"""
import sys, time
from pymavlink import mavutil
port, baud = sys.argv[1], int(sys.argv[2]); cmds = sys.argv[3:]
DEV = mavutil.mavlink.SERIAL_CONTROL_DEV_SHELL
FL = mavutil.mavlink.SERIAL_CONTROL_FLAG_RESPOND | mavutil.mavlink.SERIAL_CONTROL_FLAG_EXCLUSIVE

m = mavutil.mavlink_connection(port, baud=baud)
m.wait_heartbeat(timeout=15); print("heartbeat ok\n", flush=True)

def tx(payload=b"", timeout=0):
    d = list(payload[:70]) + [0]*(70-len(payload[:70]))
    m.mav.serial_control_send(timeout, 0, DEV, FL, len(payload[:70]), d)

def pump(sec):
    out = b""; t0 = time.time(); last = 0
    while time.time()-t0 < sec:
        if time.time()-last > 0.2:      # ★ keep-alive：每 200ms 喂一次空请求
            tx(b""); last = time.time()
        msg = m.recv_match(type='SERIAL_CONTROL', blocking=True, timeout=0.15)
        if msg and msg.count > 0:
            out += bytes(msg.data[:msg.count])
    return out

pump(1.5)
for c in cmds:
    print(f"$ {c}", flush=True)
    tx((c+"\n").encode())
    o = pump(2.5)
    t = o.decode('utf-8','replace').strip()
    print(("  " + t.replace("\n","\n  ")) if t else "  (无输出)", flush=True)
    print(flush=True)
