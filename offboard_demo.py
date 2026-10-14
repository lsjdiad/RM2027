#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PX4 SITL Offboard 演示：用程序控制无人机「前后左右飞」和「姿态飞行」。

PX4 里一共有三条「程序能插进来」的控制链路，这个脚本把三条都演一遍：

  pos       位置 setpoint   -> mc_pos_control    给 NED 坐标点，飞控自己算姿态和油门
  square    速度 setpoint   -> mc_pos_control    给 NED 速度，像「自动挡」
  attitude  姿态 setpoint   -> mc_att_control    给横滚/俯仰/偏航角 + 油门，自己当飞手

用法：
    python3 offboard_demo.py square     # 起飞 3m，前→右→后→左，飞一个 3m 的正方形
    python3 offboard_demo.py pos        # 同上，但用坐标点走四个角
    python3 offboard_demo.py attitude   # 姿态飞行：横滚左右摆 + 低头向前加速

前提：
    1. SITL 已经跑起来（~/RM2027/start-sitl.sh）
    2. 用 onboard 链路（14540/14580），QGC 走 14550，可以同时开

坐标系（NED，别搞反）：
    x = 北 = 前    y = 东 = 右    z = 下（所以 -z 才是离地高度）
    横滚 roll 正 = 右侧下沉   俯仰 pitch 正 = 抬头   偏航 yaw 正 = 右转
"""

import argparse
import math
import sys
import threading
import time

from pymavlink import mavutil

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

PX4_MAIN_MODE_ALTCTL = 2
PX4_MAIN_MODE_POSCTL = 3
PX4_MAIN_MODE_OFFBOARD = 6

MAV_MODE_FLAG_CUSTOM_MODE_ENABLED = 1

FRAME_LOCAL_NED = mavutil.mavlink.MAV_FRAME_LOCAL_NED
M = mavutil.mavlink

# 「忽略」位：置 1 = 这个字段我不管
POS_IGNORE_POS = (
    M.POSITION_TARGET_TYPEMASK_X_IGNORE
    | M.POSITION_TARGET_TYPEMASK_Y_IGNORE
    | M.POSITION_TARGET_TYPEMASK_Z_IGNORE
)
POS_IGNORE_VEL = (
    M.POSITION_TARGET_TYPEMASK_VX_IGNORE
    | M.POSITION_TARGET_TYPEMASK_VY_IGNORE
    | M.POSITION_TARGET_TYPEMASK_VZ_IGNORE
)
POS_IGNORE_ACC = (
    M.POSITION_TARGET_TYPEMASK_AX_IGNORE
    | M.POSITION_TARGET_TYPEMASK_AY_IGNORE
    | M.POSITION_TARGET_TYPEMASK_AZ_IGNORE
)
POS_IGNORE_YAW = M.POSITION_TARGET_TYPEMASK_YAW_IGNORE
POS_IGNORE_YAW_RATE = M.POSITION_TARGET_TYPEMASK_YAW_RATE_IGNORE
POS_FORCE = M.POSITION_TARGET_TYPEMASK_FORCE_SET

# 姿态 setpoint：忽略三个角速率，只给四元数 + 油门
ATT_IGNORE_RATES = (
    M.ATTITUDE_TARGET_TYPEMASK_BODY_ROLL_RATE_IGNORE
    | M.ATTITUDE_TARGET_TYPEMASK_BODY_PITCH_RATE_IGNORE
    | M.ATTITUDE_TARGET_TYPEMASK_BODY_YAW_RATE_IGNORE
)

SETPOINT_HZ = 50  # PX4 要求持续给 setpoint；低于 2Hz 会触发 offboard 失联保护

# 安全边界（撞到就自动回退到位置环并降落）
MAX_ALT = 6.0
MAX_DIST = 12.0


def set_mode_custom(mav, sysid, compid, main_mode, sub_mode=0):
    """用 PX4 的 custom_mode 编码切模式（pymavlink 没有 PX4 的模式映射表）。"""
    custom_mode = (sub_mode << 24) | (main_mode << 16)
    mav.mav.set_mode_send(sysid, MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, custom_mode)


def quat_from_euler(roll_deg, pitch_deg, yaw_deg):
    """ZYX 顺序的欧拉角 -> 四元数 (w, x, y, z)，就是 MAVLink 要的顺序。"""
    r, p, y = (math.radians(a) / 2.0 for a in (roll_deg, pitch_deg, yaw_deg))
    cr, sr = math.cos(r), math.sin(r)
    cp, sp = math.cos(p), math.sin(p)
    cy, sy = math.cos(y), math.sin(y)
    return [
        cr * cp * cy + sr * sp * sy,
        sr * cp * cy - cr * sp * sy,
        cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy,
    ]


class Drone:
    def __init__(self, port):
        print(f"[link] 监听 udp 0.0.0.0:{port}（PX4 onboard 链路）")
        self.m = mavutil.mavlink_connection(
            f"udpin:0.0.0.0:{port}", source_system=255, source_component=190
        )
        print("[link] 等心跳 ...")
        self.m.wait_heartbeat(timeout=30)
        self.sysid = self.m.target_system
        self.compid = self.m.target_component
        print(f"[link] 连上了 sysid={self.sysid} compid={self.compid}")

        # 遥测缓存：后台线程收消息，主线程只读
        self.pos = [0.0, 0.0, 0.0]  # NED：x 前, y 右, z 下
        self.att = [0.0, 0.0, 0.0]  # roll, pitch, yaw (deg)
        self.armed = False
        self.nav_state = -1
        self._stop = False
        self._lock = threading.Lock()

        self._start_threads()
        self._request_streams()

    # -- 后台线程 ---------------------------------------------------------
    def _start_threads(self):
        threading.Thread(target=self._recv_loop, daemon=True).start()
        threading.Thread(target=self._hb_loop, daemon=True).start()

    def _hb_loop(self):
        # 必须发 GCS 类型心跳：x500 机架设了 NAV_DLL_ACT 2，
        # 没有 GCS 心跳时 commander 会拦住解锁（Preflight Fail: No connection to the GCS）
        while not self._stop:
            self.m.mav.heartbeat_send(
                M.MAV_TYPE_GCS, M.MAV_AUTOPILOT_INVALID, 0, 0, 0
            )
            time.sleep(0.5)

    def _recv_loop(self):
        while not self._stop:
            try:
                msg = self.m.recv_match(blocking=True, timeout=0.5)
            except Exception:
                continue
            if msg is None:
                continue
            t = msg.get_type()
            with self._lock:
                if t == "LOCAL_POSITION_NED":
                    self.pos = [msg.x, msg.y, msg.z]
                elif t == "ATTITUDE":
                    self.att = [
                        math.degrees(msg.roll),
                        math.degrees(msg.pitch),
                        math.degrees(msg.yaw),
                    ]
                elif t == "HEARTBEAT" and msg.get_srcSystem() == self.sysid:
                    self.armed = bool(
                        msg.base_mode & M.MAV_MODE_FLAG_SAFETY_ARMED
                    )
                    self.nav_state = (msg.custom_mode >> 16) & 0xFF

    def _request_streams(self):
        """onboard 链路默认不发这些遥测，主动要。"""
        for msg_id, us in [
            (M.MAVLINK_MSG_ID_LOCAL_POSITION_NED, 20000),
            (M.MAVLINK_MSG_ID_ATTITUDE, 20000),
        ]:
            self.m.mav.command_long_send(
                self.sysid,
                self.compid,
                M.MAV_CMD_SET_MESSAGE_INTERVAL,
                0,
                msg_id,
                us,
                0,
                0,
                0,
                0,
                0,
            )

    # -- 状态读取 ---------------------------------------------------------
    @property
    def alt(self):
        with self._lock:
            return -self.pos[2]

    @property
    def dist(self):
        with self._lock:
            return math.hypot(self.pos[0], self.pos[1])

    def snapshot(self):
        with self._lock:
            return list(self.pos), list(self.att), self.armed

    # -- setpoint 发送 ----------------------------------------------------
    def _now_ms(self):
        return int(time.time() * 1000) & 0xFFFFFFFF

    def send_pos(self, x, y, z, yaw=0.0):
        """位置 setpoint：z 向下为正，想到 3m 高就传 z=-3。"""
        mask = POS_IGNORE_VEL | POS_IGNORE_ACC | POS_IGNORE_YAW_RATE
        self.m.mav.set_position_target_local_ned_send(
            self._now_ms(), self.sysid, self.compid, FRAME_LOCAL_NED, mask,
            x, y, z, 0, 0, 0, 0, 0, 0, yaw, 0,
        )

    def send_vel(self, vx, vy, vz, yaw=0.0):
        """速度 setpoint：vx 正 = 向前，vy 正 = 向右，vz 正 = 向下。"""
        mask = POS_IGNORE_POS | POS_IGNORE_ACC | POS_IGNORE_YAW_RATE
        self.m.mav.set_position_target_local_ned_send(
            self._now_ms(), self.sysid, self.compid, FRAME_LOCAL_NED, mask,
            0, 0, 0, vx, vy, vz, 0, 0, 0, yaw, 0,
        )

    def send_att(self, roll, pitch, yaw, thrust):
        """姿态 setpoint：给角度 + 归一化油门（0~1），高度不再自动保持。"""
        q = quat_from_euler(roll, pitch, yaw)
        self.m.mav.set_attitude_target_send(
            self._now_ms(), self.sysid, self.compid, ATT_IGNORE_RATES,
            q, 0, 0, 0, thrust,
        )

    # -- 通用执行 ---------------------------------------------------------
    def stream(self, fn, seconds, freq=SETPOINT_HZ, watch=True):
        """按固定频率持续发 setpoint。返回 False 表示被安全边界打断。"""
        dt = 1.0 / freq
        t_end = time.monotonic() + seconds
        while time.monotonic() < t_end:
            fn()
            if watch and not self.check_safety():
                return False
            time.sleep(dt)
        return True

    def check_safety(self):
        alt, dist = self.alt, self.dist
        if alt > MAX_ALT or dist > MAX_DIST:
            print(f"\n[SAFETY] 触发边界: 高度 {alt:.1f}m / 水平 {dist:.1f}m，回退降落")
            return False
        return True

    # -- 流程 -------------------------------------------------------------
    def arm(self, force=False):
        print("[flow] 解锁")
        self.m.mav.command_long_send(
            self.sysid, self.compid, M.MAV_CMD_COMPONENT_ARM_DISARM, 0,
            1, 21196 if force else 0, 0, 0, 0, 0, 0,
        )
        for _ in range(100):
            if self.snapshot()[2]:
                print("[flow] 已解锁")
                return True
            if not self.stream(lambda: None, 0.1, watch=False):
                pass
        raise RuntimeError("解锁失败（看 SITL 终端的报错）")

    def disarm(self):
        self.m.mav.command_long_send(
            self.sysid, self.compid, M.MAV_CMD_COMPONENT_ARM_DISARM, 0,
            0, 0, 0, 0, 0, 0, 0,
        )
        time.sleep(1.0)
        print("[flow] 已上锁")

    def start_offboard(self):
        """必须先有 setpoint 流，再切 OFFBOARD，否则飞控拒绝切模式。"""
        print("[flow] 预热 setpoint 流 -> 切 OFFBOARD")
        self.stream(lambda: self.send_pos(0, 0, -1.0), 0.6, watch=False)
        set_mode_custom(self.m, self.sysid, self.compid, PX4_MAIN_MODE_OFFBOARD)
        for _ in range(100):
            if self.nav_state == PX4_MAIN_MODE_OFFBOARD:
                print("[flow] 已进入 OFFBOARD")
                return
            time.sleep(0.1)
        print("[warn] 没确认到 OFFBOARD，继续（看 SITL 终端）")

    def takeoff(self, alt=3.0):
        print(f"[flow] 起飞到 {alt}m（offboard 模式下的位置 setpoint）")
        ok = self.stream(lambda: self.send_pos(0, 0, -alt), 20.0)
        while self.alt < alt - 0.4:
            self.send_pos(0, 0, -alt)
            if not self.check_safety():
                break
            time.sleep(0.02)
        print(f"[flow] 当前高度 {self.alt:.2f}m")

    def land(self):
        print("[flow] 分步下降 -> 上锁")
        for z in [-1.5, -0.8, -0.4, -0.15, 0.0]:
            self.stream(lambda z=z: self.send_pos(0, 0, z), 1.5, watch=False)
        time.sleep(1.0)
        self.disarm()

    def hold(self, seconds, x=0.0, y=0.0, alt=3.0):
        self.stream(lambda: self.send_pos(x, y, -alt), seconds)

    def bailout(self):
        """姿态模式出问题时回退：位置环接管 -> 回原点降落。"""
        print("[flow] 回退到位置环")
        self.stream(lambda: self.send_pos(self.pos[0], self.pos[1], -1.5), 2.0, watch=False)
        self.stream(lambda: self.send_pos(0, 0, -1.5), 5.0, watch=False)
        self.land()


# ---------------------------------------------------------------------------
# 三个演示
# ---------------------------------------------------------------------------

def demo_pos(d, alt=3.0, side=2.0):
    """位置 setpoint：直接给四个角的 NED 坐标。"""
    d.takeoff(alt)
    corners = [("前", side, 0), ("右", side, side), ("后", 0, side), ("左", 0, 0)]
    for name, x, y in corners:
        print(f"  -> {name}：目标 NED ({x:.1f}, {y:.1f})")
        d.stream(lambda x=x, y=y: d.send_pos(x, y, -alt), 4.0)
        print(f"     实际 NED ({d.pos[0]:.2f}, {d.pos[1]:.2f})  高度 {d.alt:.2f}m")
    d.hold(1.0)
    d.land()


def demo_square(d, alt=3.0, side=3.0, speed=1.0):
    """速度 setpoint：给「往哪走、多快」，方向偏了飞控自己纠。"""
    d.takeoff(alt)
    leg = side / speed
    for name, (vx, vy) in [
        ("前", (speed, 0)),
        ("右", (0, speed)),
        ("后", (-speed, 0)),
        ("左", (0, -speed)),
    ]:
        print(f"  -> {name}：速度 NED ({vx:+.1f}, {vy:+.1f}) m/s, {leg:.1f}s")
        d.stream(lambda vx=vx, vy=vy: d.send_vel(vx, vy, 0), leg)
        print(f"     实际 NED ({d.pos[0]:.2f}, {d.pos[1]:.2f})  高度 {d.alt:.2f}m")
    print("  -> 刹停")
    d.stream(lambda: d.send_vel(0, 0, 0), 2.0)
    d.land()


def demo_attitude(d, alt=3.0, thrust=0.6):
    """姿态 setpoint：只给角度和油门，高度要自己操心。"""
    d.takeoff(alt)

    print(f"[flow] 切到姿态链路：油门固定 {thrust}（x500 的 MPC_THR_HOVER 是 0.6）")
    print("       注意：姿态模式没有高度闭环，飞机会自己缓慢掉高/爬升，这是正常的")
    roll_deg, pitch_deg = d.att[0], d.att[1]

    # 用 2 秒平滑过渡到当前姿态，避免角度突跳
    d.stream(lambda: d.send_att(roll_deg, pitch_deg, 0, thrust), 2.0)
    start_alt = d.alt

    print("  -> 横滚：右 12 度（会向右平移）")
    for a in (12, 12, 12):
        if not d.stream(lambda: d.send_att(a, 0, 0, thrust), 0.7):
            return d.bailout()
    print(f"     横滚 {d.att[0]:+.1f} 度，实际 NED ({d.pos[0]:.2f}, {d.pos[1]:.2f}), {d.alt:.2f}m")

    print("  -> 回正")
    d.stream(lambda: d.send_att(6, 0, 0, thrust), 0.5)

    print("  -> 横滚：左 12 度")
    for a in (-12, -12, -12):
        if not d.stream(lambda: d.send_att(a, 0, 0, thrust), 0.7):
            return d.bailout()

    print("  -> 回正后低头 10 度（pitch 负 = 低头 -> 向前加速）")
    d.stream(lambda: d.send_att(0, 0, 0, thrust), 1.0)
    for p in (-10, -10, -10):
        if not d.stream(lambda: d.send_att(0, p, 0, thrust), 0.7):
            return d.bailout()
    print(f"     俯仰 {d.att[1]:+.1f} 度，实际 NED ({d.pos[0]:.2f}, {d.pos[1]:.2f}), {d.alt:.2f}m")

    print("  -> 抬头 10 度（刹车）")
    for p in (10, 10):
        if not d.stream(lambda: d.send_att(0, p, 0, thrust), 0.7):
            return d.bailout()

    print(f"[flow] 姿态演示结束：高度 {start_alt:.2f} -> {d.alt:.2f}m（掉高就是因为没有高度闭环）")
    print("[flow] 回退到位置环，准备降落")
    d.bailout()


DEMOS = {
    "pos": demo_pos,
    "square": demo_square,
    "attitude": demo_attitude,
}


def main():
    ap = argparse.ArgumentParser(description="PX4 SITL offboard 演示")
    ap.add_argument("mode", choices=sorted(DEMOS), help="演示哪种 setpoint")
    ap.add_argument("--port", type=int, default=14540, help="onboard 链路端口")
    ap.add_argument("--alt", type=float, default=3.0, help="起飞高度 (m)")
    args = ap.parse_args()

    d = Drone(args.port)
    try:
        d.arm()
        d.start_offboard()
        DEMOS[args.mode](d, alt=args.alt)
    except KeyboardInterrupt:
        print("\n[!] 手动中断")
    except Exception as e:
        print(f"\n[!] 出错：{e}")
        try:
            d.bailout()
        except Exception:
            pass
    finally:
        d._stop = True
        time.sleep(0.3)


if __name__ == "__main__":
    sys.exit(main())
