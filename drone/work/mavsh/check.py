import time, collections
from pymavlink import mavutil
m = mavutil.mavlink_connection('/dev/ttyUSB0', baud=57600)
m.wait_heartbeat(timeout=20); print("心跳 OK", flush=True)
# 主动发心跳，让 PX4 认为有 GCS 连着，开数据流
for _ in range(20):
    m.mav.heartbeat_send(mavutil.mavlink.MAV_TYPE_GCS, mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0,0,0)
    time.sleep(0.1)
cnt=collections.Counter(); t0=time.time()
while time.time()-t0 < 8:
    msg = m.recv_match(blocking=True, timeout=0.3)
    if msg: cnt[msg.get_type()] += 1
print("8 秒内收到的消息类型：", flush=True)
for k,v in cnt.most_common(25): print(f"   {k:28s} x{v}")
KEY=['ATTITUDE','RAW_IMU','HIGHRES_IMU','SCALED_IMU','SCALED_IMU2','SCALED_IMU3','SCALED_PRESSURE','AHRS2','LOCAL_POSITION_NED','GLOBAL_POSITION_INT','SYS_STATUS']
print("\n★ 关键判据：", flush=True)
for k in KEY: print(f"   {k:24s} {'✅ 有' if cnt.get(k) else '❌ 无'}")
