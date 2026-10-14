#!/usr/bin/env python3
"""
AM32 闭环换相时序自洽性检验（纯运动学 + 梯形反电势）

目的：判定 ISR 里这个"过零门槛"
        INTERVAL_TIMER->CNT > (average_interval >> 1)
   与【物理过零时刻】是否对得上。

物理事实（六步换相 + 梯形反电势）：
  换相一次前进 60° 电角度；悬空相的反电势在换相后约 30° 处过零
  ⇒ 过零发生在【半个换相步】之后。

代码事实：
  e_com_time      = ((sum of 6 commutation_intervals) + 4) >> 1   (main.c:2227)
  average_interval= e_com_time / 3                               (main.c:2392)
  commutation_intervals[k] = commutation_interval 的【历史值】 (main.c:930)
  INTERVAL_TIMER  = 2MHz 自由运行 ⇒ 1 拍 = 0.5µs
  commutation_interval 的单位也是 0.5µs/拍
"""
STEP_TICKS = 900          # 一个换相步 = 900 拍 = 450µs（≈3700 机械 RPM，6 对极）

# --- 稳态下 average_interval 的值（按代码公式算） ---
ci = STEP_TICKS                      # 稳态：commutation_interval 收敛到"一个换相步"
intervals = [ci]*6
e_com_time = (sum(intervals) + 4) >> 1
average_interval = e_com_time // 3

print(f"一个换相步          = {STEP_TICKS} 拍")
print(f"e_com_time          = {e_com_time} 拍")
print(f"average_interval    = {average_interval} 拍  (= e_com_time/3)")
print(f"门槛 average_interval>>1 = {average_interval>>1} 拍")
print()
print(f"⇒ 门槛在换相后 {average_interval>>1} 拍拍开")
print(f"  而物理过零发生在换相后 {STEP_TICKS//2} 拍")
ratio = (average_interval>>1) / (STEP_TICKS/2)
print(f"⇒ 门槛比物理过零【晚 {ratio:.1f} 倍】")
print()

# 上界
upper = average_interval << 1
print(f"上界 = average_interval<<1 = {upper} 拍")
print(f"⇒ 接受窗口 = [{average_interval>>1}, {upper}) = 换相后 "
      f"{ratio:.1f} ~ {upper/STEP_TICKS:.1f} 个换相步")
print()
print("结论：物理过零（0.5 步）落在接受窗口【之外】（窗口从 1.0 步才开始）")
