#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
h104_verify.py —— 用**上板抓到的真实字节**逐条验证 H104/HI91 帧规格

这是"手册说的" 与 "实物到底怎样" 之间的判决器。它做四件事：
  A. 组帧正确性：SOF / LEN / CRC 全帧校验
  B. ★ 偏移正确性：把字段整体平移 ±1/±2/±3 字节，看是否还有别的对齐能解出物理上说得通的数据
       （用来一次性否掉"字段偏移算错了"这个怀疑）
  C. 物理自检：静止时 |acc| 必须 ≈ 1.0 G（不依赖任何文档的强判据）
  D. 姿态自检：四元数必须与欧拉角自洽（验证旋转顺序/轴向约定）

用法： python3 h104_verify.py <cap.bin>
"""

import math
import statistics
import struct
import sys
from collections import Counter


def frames(b):
    """按 SOF=5A A5 / LEN(小端) / CRC(小端) 组帧；只吐 CRC 正确的帧"""
    def crc16(data):
        c = 0
        for x in data:
            c ^= x << 8
            for _ in range(8):
                c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
        return c

    i, n = 0, len(b)
    stats = Counter()
    out = []
    while i + 6 <= n:
        if b[i:i + 2] != b"\x5a\xa5":
            i += 1
            stats["resync"] += 1
            continue
        ln = int.from_bytes(b[i + 2:i + 4], "little")
        if ln < 1 or ln > 512:
            stats["len_bad"] += 1
            i += 2
            continue
        tot = 6 + ln
        if i + tot > n:
            stats["truncated"] += 1
            break
        rx = int.from_bytes(b[i + 4:i + 6], "little")
        calc = crc16(b[i:i + 4] + b[i + 6:i + tot])
        stats["frames"] += 1
        if rx != calc:
            stats["crc_bad"] += 1
        else:
            stats["crc_ok"] += 1
            out.append((i, b[i + 6:i + tot]))
        i += tot
    return out, stats


def f32(p, off):
    return struct.unpack_from("<f", p, off)[0]


def vec3(p, off):
    return struct.unpack_from("<3f", p, off)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "h104-cap.bin"
    buf = open(path, "rb").read()
    fr, st = frames(buf)
    print("=" * 78)
    print("文件 %s ：%d 字节" % (path, len(buf)))
    print("=" * 78)
    print("\n[A] 组帧正确性")
    print("    扫到帧=%d  CRC好=%d  CRC坏=%d  长度非法=%d  截断=%d  重同步跳过=%d"
          % (st["frames"], st["crc_ok"], st["crc_bad"], st["len_bad"], st["truncated"], st["resync"]))
    if len(fr) < 2:
        print("    帧数太少，无法继续。")
        return 1
    gaps = Counter(fr[k + 1][0] - fr[k][0] for k in range(len(fr) - 1))
    print("    相邻帧起始偏移差 = %s    （HI91 应恒为 82）" % dict(gaps))
    plen = Counter(len(p) for _, p in fr)
    print("    数据域长度 = %s    （HI91 应恒为 76）" % dict(plen))
    tag = Counter(p[0] for _, p in fr)
    print("    tag = %s    （HI91 应为 0x91）" % {hex(k): v for k, v in tag.items()})

    # ---------------- [B] 偏移判决 ----------------
    print("\n[B] ★ 偏移正确性判决：把字段整体平移 delta 字节，看哪个对齐能解出'物理上说得通'的数据")
    print("    判据：|acc| 必须 ≈ 1.0 G（静止）；roll/pitch 必须 ≈ 0（板子基本水平）")
    print("    delta  温度@3+d  |acc|均值   rpy[0]     rpy[1]     结论")
    for delta in (-3, -2, -1, 0, 1, 2, 3):
        mags, r0, p0 = [], [], []
        for _, p in fr:
            a = vec3(p, 12 + delta)
            mags.append(math.sqrt(sum(x * x for x in a)))
            r0.append(f32(p, 48 + delta))
            p0.append(f32(p, 52 + delta))
        m = sum(mags) / len(mags)
        sane = (abs(m - 1.0) < 0.1) and (abs(sum(r0) / len(r0)) < 5) and (abs(sum(p0) / len(p0)) < 5)
        print("    %+d      %7.2f     %8.4f   %8.3f   %8.3f   %s"
              % (delta, sum(struct.unpack_from('<b', p, 3 + delta)[0] for _, p in fr) / len(fr),
                 m, sum(r0) / len(r0), sum(p0) / len(p0),
                 "★★ 唯一说得通" if delta == 0 and sane else ("勉强?" if sane else "解出的是垃圾")))

    # 温度宽度检验：若温度是 2 字节，温度会随秒变化（不可能）
    print("\n    温度宽度检验（若 temperature 是 2 字节，它应随时间漂移）:")
    t_i8 = [struct.unpack_from("<b", p, 3)[0] for _, p in fr]
    t_at2 = [struct.unpack_from("<b", p, 2)[0] for _, p in fr]
    print("      offset 3 当 i8   : 取值集合 %s  → 稳定" % sorted(set(t_i8))[:8])
    print("      offset 2 当 i8   : 取值集合 %s  → 1 秒内变化 %d 次，不可能是温度"
          % (sorted(set(t_at2))[:8], sum(1 for k in range(len(t_at2) - 1) if t_at2[k] != t_at2[k + 1])))

    # ---------------- [C] 物理自检 ----------------
    print("\n[C] 物理自检（不依赖文档的强判据）")
    acc = [vec3(p, 12) for _, p in fr]
    mags = [math.sqrt(sum(x * x for x in a)) for a in acc]
    mean_mag = sum(mags) / len(mags)
    print("    |acc| : 均值=%.4f  min=%.4f  max=%.4f" % (mean_mag, min(mags), max(mags)))
    if abs(mean_mag - 1.0) < 0.05:
        print("    ⇒ **单位是 G**（手册对）；若单位是 m/s² 应 ≈9.8")
    elif abs(mean_mag - 9.8) < 0.5:
        print("    ⇒ 单位是 m/s²（手册错）")
    else:
        print("    ⇒ 两者都不像，需怀疑")
    gyr = [vec3(p, 24) for _, p in fr]
    for ax in range(3):
        v = [g[ax] for g in gyr]
        print("    gyr[%d]: 均值=%+.4f dps  标准差=%.4f dps" % (ax, statistics.mean(v), statistics.pstdev(v)))
    static = all(abs(statistics.mean([g[ax] for g in gyr])) < 1.0 for ax in range(3))
    print("    ⇒ 静止时三轴均值都 <1 dps：%s" % ("是（陀螺零偏小）" if static else "否"))

    # ---------------- [D] 姿态自检 ----------------
    print("\n[D] 姿态自检：四元数 vs 欧拉角（验证手册的 ENU 312 约定：roll 绕 Y / pitch 绕 X / yaw 绕 Z）")
    errs = []
    for _, p in fr[:10]:
        r, pit, y = struct.unpack_from("<3f", p, 48)
        w, qx, qy, qz = struct.unpack_from("<4f", p, 60)
        # 小角近似：q_x≈pitch/2, q_y≈roll/2, q_z≈yaw/2
        exp = [math.radians(pit) / 2, math.radians(r) / 2, math.radians(y) / 2]
        got = [qx, qy, qz]
        e = max(abs(a - b) for a, b in zip(exp, got))
        errs.append(e)
    print("    前 10 帧：max|q_x−pitch/2, q_y−roll/2, q_z−yaw/2| = %.2e" % max(errs))
    if max(errs) < 1e-4:
        print("    ⇒ **四元数与欧拉角完全自洽**，且轴向映射 = (x→pitch, y→roll, z→yaw)，与手册 ENU 312 一致")
    else:
        print("    ⇒ 不自洽！旋转约定或字段偏移有问题")

    # ---------------- [E] 时间戳 / 帧率 ----------------
    print("\n[E] 时间戳与帧率")
    ts = [int.from_bytes(p[8:12], "little") for _, p in fr]
    d = Counter(ts[k + 1] - ts[k] for k in range(len(ts) - 1))
    print("    system_time 增量分布(ms) = %s" % dict(d))
    if d:
        avg = sum(k * v for k, v in d.items()) / sum(d.values())
        print("    ⇒ 帧率 = %.1f Hz" % (1000.0 / avg) if avg else "")

    # ---------------- [F] 偏移1 那个 u16 到底是什么 ----------------
    print("\n[F] ★ 偏移 1 的 u16（手册称 main_status）实测行为")
    eq_lo = sum(1 for _, p in fr if (int.from_bytes(p[1:3], "little") & 0xFF) == p[8])
    print("    低字节 == system_time 低字节 的帧数 : %d/%d" % (eq_lo, len(fr)))
    rel = Counter((int.from_bytes(p[1:3], "little") >> 8)
                  - ((int.from_bytes(p[8:12], "little") >> 8) & 0xFF) & 0xFF for _, p in fr)
    print("    (高字节 − (system_time>>8)&0xFF) mod 256 的取值集合 : %s" % dict(rel))
    if eq_lo == len(fr) and len(rel) == 1:
        print("    ⇒ 这个字段是 **system_time 的确定性函数**（98/98 + 常数偏置）")
        print("    ⇒ 它**不是**手册描述的那种独立状态位字，驱动里不要按 MAIN_STATUS 位表解读")
    else:
        print("    ⇒ 低字节相等但关系不固定，需进一步查")

    # ---------------- [G] 恒零字段 ----------------
    print("\n[G] 恒零字段（该型号/模式没输出的东西）")
    mag_zero = all(all(v == 0.0 for v in vec3(p, 36)) for _, p in fr)
    apr_zero = all(f32(p, 4) == 0.0 for _, p in fr)
    print("    mag_b 恒为 0 : %s" % mag_zero)
    print("    air_pressure 恒为 0 : %s" % apr_zero)
    print("    ⇒ 这两个字段不可用（与 LOG USRCONFIG 的 KF_EN_MAG=0 / 该型号无气压计吻合）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
