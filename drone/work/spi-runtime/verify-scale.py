#!/usr/bin/env python3
# verify-scale.py —— 离线核算：把实机抓到的原始字节，按 BMI270::DataReadPublish() 的
# 代码语义（MSB-first 解析 → (x,-y,-z) → 乘 scale）走一遍，看发布出去的值是否合理。
#
# 输入的原始字节来自 datadump.log（64 个突发读样本，板子静止平放）。
# 这不是替代上板验证，而是把「标定系数 + 符号约定 + 字节序」三者做一次自洽核算。
import re, math, statistics

ONE_G = 9.80665
CORR  = 2048.0 / 1185.0                    # == BMI270.hpp 的 ACCEL_COMPAT_GAIN_CORRECTION
ACC_RANGE_CODE = 0x03                      # PX4 驱动写进 ACC_RANGE 的值（名义 16g）
scale_acc = 16.0 * ONE_G / 32768.0 * CORR  # == SetAccelScaleAndRange() 的结果
scale_gyr = math.radians(2000.0) / 32767.0 # == SetGyroScale()，手册 2000dps 满量程

def s16(msb, lsb):
    v = (msb << 8) | lsb
    return v - 65536 if v >= 32768 else v

rows = []
for line in open('datadump.log'):
    m = re.match(r'^T\d+ ([0-9A-F]{24})', line.strip())
    if m:
        rows.append(m.group(1))

acc, gyr = [], []
for h in rows:
    d = [int(h[j:j+2], 16) for j in range(0, 24, 2)]   # data[0..11] ≡ DataReadBuffer.data
    ax, ay, az = s16(d[0], d[1]), s16(d[2], d[3]), s16(d[4], d[5])
    gx, gy, gz = s16(d[6], d[7]), s16(d[8], d[9]), s16(d[10], d[11])
    # 代码实际发布的：(x, -y, -z) 再乘 scale（rotation=0 ⇒ rotate_3f 恒等）
    acc.append((ax*scale_acc, -ay*scale_acc, -az*scale_acc))
    gyr.append((gx*scale_gyr, -gy*scale_gyr, -gz*scale_gyr))

mag = [math.sqrt(sum(v*v for v in a)) for a in acc]
print("样本数 = %d" % len(rows))
print("scale_acc = %.9f m/s^2/count" % scale_acc)
print("sensor_accel: x=%+.4f  y=%+.4f  z=%+.4f  |a|=%.4f ± %.4f m/s^2 (误差 %+.2f%%)" % (
    statistics.mean(a[0] for a in acc), statistics.mean(a[1] for a in acc),
    statistics.mean(a[2] for a in acc), statistics.mean(mag), statistics.pstdev(mag),
    (statistics.mean(mag)/ONE_G - 1)*100))
print("未修正时 |a| = %.4f m/s^2 (0.578g) —— 这正是要修正的原因" % (statistics.mean(mag)/CORR))
gm = [math.sqrt(sum(v*v for v in g)) for g in gyr]
print("sensor_gyro: 静止 |w| = %.3f dps（零偏量级，正常）" % math.degrees(statistics.mean(gm)))
