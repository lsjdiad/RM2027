#!/usr/bin/env python3
"""
最干净的测量：转子以稳定电角速度旋转，换相步按"每步 60°"正确推进，
直接测：换相后经过多少【拍】，悬空相反电势才过零。
"""
import math

TICK = 0.5e-6
STEP_TICKS = 900            # 一个换相步 = 900 拍 = 450µs
# 电角速度：60° = pi/3 rad 用时 900 拍
w_e = (math.pi/3) / (STEP_TICKS*TICK)      # rad/s

PHI = {'A': 0.0, 'B': 2*math.pi/3, 'C': 4*math.pi/3}
STEPS = {1:('A','B','C'),2:('C','B','A'),3:('C','A','B'),
         4:('B','A','C'),5:('B','C','A'),6:('A','C','B')}

def trap(theta):
    t = math.degrees(theta % (2*math.pi))
    if t < 60:   return t/60.0
    if t < 180:  return 1.0
    if t < 240:  return 1.0 - (t-180)/30.0
    return -1.0

print(f"一个换相步 = {STEP_TICKS} 拍")
print()
print("step | 换相瞬间悬空相反电势 | 过零发生在换相后多少拍 | 与步长之比")
for s in range(1, 7):
    _, _, fp = STEPS[s]
    # 换相瞬间的转子角：取该步定子磁场角 - 30°（标准对齐）
    AXIS = {'A':0.0,'B':120.0,'C':240.0}
    pwm, low, _ = STEPS[s]
    a1, a2 = math.radians(AXIS[pwm]), math.radians(AXIS[low]+180.0)
    stator = math.atan2(math.sin(a1)+math.sin(a2), math.cos(a1)+math.cos(a2))
    for lead_deg in (30.0,):
        theta0 = stator - math.radians(lead_deg)
        e0 = trap(theta0 - PHI[fp])
        # 扫描寻找过零
        found = None
        prev = e0
        for k in range(1, STEP_TICKS*3):
            th = theta0 + w_e*k*TICK
            cur = trap(th - PHI[fp])
            if (prev > 0) != (cur > 0):
                found = k
                break
            prev = cur
        print(f"  {s}  |     {e0:+.2f}          |        {found} 拍"
              f"          |   {found/STEP_TICKS:.2f}")
