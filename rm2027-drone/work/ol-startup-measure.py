#!/usr/bin/env python3
"""开环「起步瞬间」电源/占空比测量 —— 判断"没劲"到底是电源限流还是扭矩不足。

用法：python3 ol-startup-measure.py [采样次数] [间隔ms]     默认 24 次 × 400ms ≈ 10 秒
放行后在一个 openocd 会话里连采（只在快照瞬间 halt 几十 ms），结束自动锁回。
任何异常退出路径都会写回 hold_zero=1。

★ 地址随固件漂移 —— 换固件必须用 nm 重取！当前 = 提交 296a3ef 版（开环基准）。
"""

import subprocess, re, time, sys, atexit, os

ST = ["openocd", "-f", "interface/stlink.cfg", "-f", "target/stm32g0x.cfg",
      "-c", "adapter speed 500"]
JL = ["openocd", "-f", "interface/jlink.cfg", "-c", "transport select swd",
      "-f", "target/stm32f1x.cfg", "-c", "adapter speed 1000"]

HOLD_ZERO = 0x20000274          # F103 的 g_dbg+120（放行/锁回控制位，这个不随电调固件变）

# ---- 296a3ef（开环基准版）电调变量地址 ----
BLK_ADDR = 0x20000624           # 这一块 16 个字里含下列全部：
A_ZC    = 0x20000624            # zero_crosses
A_RUN   = 0x20000628            # running (u8)
A_ADJ   = 0x2000062c            # adjusted_input (u16)
A_DUTY  = 0x20000630            # duty_cycle (u16 /2000)
A_ARMED = 0x20000634            # armed (u8)
A_INPUT = 0x20000636            # input (u16)
A_SET   = 0x20000644            # duty_cycle_setpoint (u16)
A_BAT   = 0x2000065c            # battery_voltage (u16, 0.01V)
A_CUR   = 0x20000662            # actual_current  (u16, 0.01A)
A_ERPM  = 0x200006b8            # e_rpm (u16)

def run(base, cmds, timeout=60):
    r = subprocess.run(base + cmds, capture_output=True, text=True, timeout=timeout)
    return r.stdout + r.stderr

def words(txt, addr):
    out, started = [], False
    for ln in txt.splitlines():
        m = re.match(r"^(0x[0-9a-f]{8}):\s*(.*)$", ln.strip())
        if not m:
            if started:
                break
            continue
        got = int(m.group(1), 16)
        if got == addr:
            started = True
        elif not started:
            continue
        elif got != addr + 4 * len(out):
            break
        out.extend(int(x, 16) for x in m.group(2).split())
    return out or None

def u8(w, i):  return (w >> (8 * i)) & 0xFF
def u16(w, k): return (w >> (16 * k)) & 0xFFFF

def parse(txt):
    b = words(txt, BLK_ADDR)
    e = words(txt, A_ERPM)
    if not b or not e:
        return None
    def lo(a):
        # ★ 按字节偏移取 u16：地址是 4 对齐取低半字，否则（2 mod 4）取高半字
        off = a - BLK_ADDR
        return u16(b[off // 4], 0 if (off % 4) == 0 else 1)
    def by(a):  return u8(b[(a - BLK_ADDR) // 4], 0)           # 该字的最低字节
    return dict(zc=lo(A_ZC), running=by(A_RUN), adj=lo(A_ADJ), duty=lo(A_DUTY),
                armed=by(A_ARMED), inp=lo(A_INPUT), setp=lo(A_SET),
                bat=lo(A_BAT), cur=lo(A_CUR), erpm=e[0])

def relock():
    run(JL, ["-c", "init", "-c", "halt", "-c", "mwb 0x%08x 1" % HOLD_ZERO,
             "-c", "resume", "-c", "shutdown"])
def release():
    run(JL, ["-c", "init", "-c", "halt", "-c", "mwb 0x%08x 0" % HOLD_ZERO,
             "-c", "resume", "-c", "shutdown"])

atexit.register(relock)

def show(s, tag):
    if not s:
        print("  %s 读失败" % tag)
        return
    print("  %-7s run=%d armed=%d duty=%4d setp=%4d adj=%4d input=%4d | "
          "母线=%-5d(%.2fV) 电流=%-5d(%.2fA) eRPM=%-5d"
          % (tag, s["running"], s["armed"], s["duty"], s["setp"], s["adj"], s["inp"],
             s["bat"], s["bat"] / 100.0, s["cur"], s["cur"] / 100.0, s["erpm"]))

n = int(sys.argv[1]) if len(sys.argv) > 1 else 24
itv = int(sys.argv[2]) if len(sys.argv) > 2 else 400

print("### 开环起步瞬间测量：%d 次 × %dms" % (n, itv))
relock()
t = run(ST, ["-c", "init", "-c", "halt", "-c", "mdw 0x%08x 16" % BLK_ADDR,
             "-c", "mdw 0x%08x 1" % A_ERPM, "-c", "resume", "-c", "shutdown"])
show(parse(t), "放行前")

print("--- 放行 ---")
release()
cmds = ["-c", "init"]
for i in range(n):
    cmds += ["-c", "echo {@R%d@}" % i, "-c", "halt",
             "-c", "mdw 0x%08x 16" % BLK_ADDR, "-c", "mdw 0x%08x 1" % A_ERPM,
             "-c", "resume", "-c", "sleep %d" % itv]
cmds += ["-c", "shutdown"]
try:
    txt = run(ST, cmds, timeout=int(30 + n * (itv / 1000.0 + 1.0)))
    for i, part in enumerate(re.split(r"@R\d+@", txt)[1:]):
        show(parse(part), "R%-2d" % i)
finally:
    relock()
    print("  → 已锁回")
