import time, collections
from pymavlink import mavutil
m = mavutil.mavlink_connection('/dev/ttyUSB0', baud=57600)
m.wait_heartbeat(timeout=15); print("heartbeat ok")
print("SERIAL_CONTROL_DEV_SHELL =", mavutil.mavlink.SERIAL_CONTROL_DEV_SHELL)
# 先看 2 秒内都收到什么消息
cnt = collections.Counter()
t0=time.time()
while time.time()-t0 < 2.5:
    msg = m.recv_match(blocking=True, timeout=0.3)
    if msg: cnt[msg.get_type()] += 1
print("静默期收到的消息:", dict(cnt))
# 发一条命令，看返回
m.mav.serial_control_send(0, 0, mavutil.mavlink.SERIAL_CONTROL_DEV_SHELL,
    mavutil.mavlink.SERIAL_CONTROL_FLAG_RESPOND|mavutil.mavlink.SERIAL_CONTROL_FLAG_EXCLUSIVE,
    8, list(b"ver all\n")+[0]*62)
cnt2 = collections.Counter(); t0=time.time(); got=[]
while time.time()-t0 < 5:
    msg = m.recv_match(blocking=True, timeout=0.3)
    if msg:
        cnt2[msg.get_type()] += 1
        if msg.get_type()=='SERIAL_CONTROL':
            got.append((msg.device, msg.count, bytes(msg.data[:max(msg.count,0)])))
print("发命令后收到的消息:", dict(cnt2))
for g in got[:10]: print("  SERIAL_CONTROL:", g)
