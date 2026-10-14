#!/usr/bin/env python3
"""ESC 闭环台架测试（RM2027 电调板 + F103 测试信号发生器）

用法：
  python3 esc-closeloop-test.py burst <n> [hyst] [pol]   # 放行 n 次采样，可选先设 hyst/pol
  python3 esc-closeloop-test.py lock                     # 只锁回（写 F103 hold_zero=1）

安全：每次放行都有硬上限；任何退出路径（含异常）都会写回 hold_zero=1 锁住。

地址（以当前固件/ELF 的 nm 为准，改固件后要重取）：
  F103 g_dbg = 0x200001FC，hold_zero = g_dbg+120 = 0x20000274
  ESC : 0x20000600 区（zero_crosses/running/newinput/duty/bemf_timeout/input/armed…）
        0x200003C8 四路 BEMF 码；0x2000005C old_routine；0x20000794 极性/武装
        0x2000066C desync_happened；0x20000670 e_rpm；0x200003C6 bemf_hyst
"""
import subprocess, re, time, sys, atexit, os

# ★ 电调变量地址【随固件漂移】—— 换固件后必须用 nm 重取（本项目纪律，已踩过多次）：
#     开环版(RM2027_OL_ARM_ONLY=1): armed=0x20000618  running=0x2000060C  duty=0x20000614
#                                    battery_voltage=0x20000640
#     闭环版:                        armed=0x20000620  running=0x20000608  duty=0x20000610
#                                    battery_voltage=0x2000064A
#   默认值 = 当前已烧的那版；用环境变量可临时覆盖，不用改代码。
ESC_ARMED = int(os.environ.get("ESC_ARMED_ADDR", "0x20000618"), 16)
ESC_VOLTS = int(os.environ.get("ESC_VOLTS_ADDR", "0x20000640"), 16)

ST = ["openocd", "-f", "interface/stlink.cfg", "-f", "target/stm32g0x.cfg",
      "-c", "adapter speed 500"]
JL = ["openocd", "-f", "interface/jlink.cfg", "-c", "transport select swd",
      "-f", "target/stm32f1x.cfg", "-c", "adapter speed 1000"]

HOLD_ZERO, POL, HYST = 0x20000274, 0x20000794, 0x200003C6
DRIVE_MAX_S = 20.0

def run(base, cmds, timeout=60):
    r = subprocess.run(base + cmds, capture_output=True, text=True, timeout=timeout)
    return r.stdout + r.stderr

def words(txt, addr):
    out, started = [], False
    for ln in txt.splitlines():
        m = re.match(r"^(0x[0-9a-f]{8}):\s*(.*)$", ln.strip())
        if not m:
            if started: break
            continue
        got = int(m.group(1), 16)
        if got == addr: started = True
        elif not started: continue
        elif got != addr + 4 * len(out): break
        out.extend(int(x, 16) for x in m.group(2).split())
    return out or None

def u8(w, i):  return (w >> (8 * i)) & 0xFF
def u16(w, k): return (w >> (16 * k)) & 0xFFFF

MDW = [
    "-c", "mdw 0x200003c6 1",   # bemf_hyst
    "-c", "mdw 0x200003c8 4",   # va vb vc v0
    "-c", "mdw 0x20000050 4",   # rising step commutation_interval
    "-c", "mdw 0x20000600 8",   # zero_crosses running newinput · duty · bemf_timeout input
    "-c", "mdw 0x20000620 1",   # armed
    "-c", "mdw 0x20000790 2",   # active_phase bemf_state pol irq_armed
    "-c", "mdw 0x2000066c 2",   # desync_happened, e_rpm
    "-c", "mdw 0x20000654 1",   # average_interval
    "-c", "mdw 0x20000638 1",   # e_com_time
    "-c", "mdw 0x200005f8 1",   # lastzctime / thiszctime
    "-c", "mdw 0x20000678 1",   # 母线 ADC 码
    "-c", "mdw 0x2000005c 1",   # old_routine
]

def esc_read(extra=None):
    txt = run(ST, ["-c", "init", "-c", "halt"] + (extra or []) + MDW
                  + ["-c", "resume", "-c", "shutdown"])
    return parse_esc(txt)

def parse_esc(txt):
    hy = words(txt, 0x200003c6); ad = words(txt, 0x200003c8); g = words(txt, 0x20000050)
    w = words(txt, 0x20000600); a = words(txt, 0x20000620); b = words(txt, 0x20000790)
    d = words(txt, 0x2000066c); ai = words(txt, 0x20000654)
    bv = words(txt, 0x20000678); m = words(txt, 0x2000005c)
    ec = words(txt, 0x20000638); zt = words(txt, 0x200005f8)
    if not (hy and ad and g and w and a and b and d and ai and bv and m and ec and zt):
        return None
    va, vb, vc, v0 = u16(ad[0],0), u16(ad[0],1), u16(ad[1],0), u16(ad[1],1)
    ap = u8(b[0], 2)
    return dict(hyst=u16(hy[0],0), va=va, vb=vb, vc=vc, v0=v0, ap=ap,
                delta={0: va-v0, 1: vb-v0, 2: vc-v0}[ap], step=u8(g[1],1),
                rising=u8(g[0],2), ci=g[2], avg_int=u16(ai[0],0),
                zc=w[1], running=u8(w[2],0), newin=u16(w[2],1), duty=w[4],
                bemfTO=u8(w[5],0), input=u16(w[5],1), armed=u8(a[0],0),
                pol=u8(b[1],0), irq=u8(b[1],1), desync=u16(d[0],0), erpm=d[1],
                bus=u16(bv[0],0), old=u8(m[0],0),
                e_com=ec[0], lastzc=u16(zt[0],0), thiszc=u16(zt[0],1),
                mean3=(va+vb+vc)//3)

def live(n, interval_ms):
    """在一个 openocd 会话里做 n 次 (halt→读→resume→sleep interval_ms)：
    目标只在每次快照时短暂停住（~几十 ms），其余时间闭环在真跑 ⇒ 采样间隔可压到 0.3s。"""
    cmds = ["-c", "init"]
    for i in range(n):
        cmds += ["-c", "echo {@R%d@}" % i, "-c", "halt"] + MDW + \
                ["-c", "resume", "-c", "sleep %d" % interval_ms]
    cmds += ["-c", "shutdown"]
    txt = run(ST, cmds, timeout=int(30 + n * (interval_ms / 1000.0 + 1.5)))
    parts = re.split(r"@R\d+@", txt)[1:]
    out = []
    for i, part in enumerate(parts):
        s = parse_esc(part)
        out.append(s)
        show(s, "R%-2d" % i)
    return out

def esc_read_u8(addr):
    """读电调某个 u8 变量（halt 一次，几十毫秒）"""
    txt = run(ST, ["-c", "init", "-c", "halt", "-c", "mdw 0x%08x 1" % addr,
                   "-c", "resume", "-c", "shutdown"])
    w = words(txt, addr)
    return None if not w else u8(w[0], 0)

def esc_read_u16(addr):
    txt = run(ST, ["-c", "init", "-c", "halt", "-c", "mdw 0x%08x 1" % addr,
                   "-c", "resume", "-c", "shutdown"])
    w = words(txt, addr)
    return None if not w else u16(w[0], 0)

def f103_read():
    txt = run(JL, ["-c","init","-c","halt","-c","mdw 0x200001fc 32",
                   "-c","resume","-c","shutdown"])
    w = words(txt, 0x200001fc)
    if not w: return None
    return dict(state=u8(w[3],0), throttle=u16(w[3],1), hold=u8(w[30],0),
                erpm_x100=u16(w[23],0), volts=u16(w[21],1), cur=u16(w[22],0),
                ok=w[18], err=w[20])

def relock():
    run(JL, ["-c","init","-c","halt","-c","mwb 0x%08x 1" % HOLD_ZERO,
             "-c","resume","-c","shutdown"])
def release():
    run(JL, ["-c","init","-c","halt","-c","mwb 0x%08x 0" % HOLD_ZERO,
             "-c","resume","-c","shutdown"])
def set_knobs(hyst, pol):
    run(ST, ["-c","init","-c","halt","-c","mwh 0x%08x %d" % (HYST, hyst),
             "-c","mwb 0x%08x %d" % (POL, pol), "-c","resume","-c","shutdown"])

atexit.register(relock)

def show(s, tag):
    if not s: print("  %s 读失败" % tag); return
    print("  %s run=%d duty=%4d newin=%4d zc=%-5d eRPM=%-6d bemfTO=%-4d desync=%-3d "
          "old=%d irq=%d | step=%d ap=%d va=%4d vb=%4d vc=%4d v0=%4d delta=%5d | ci=%-6d avg=%-6d e_com=%-7d lastzc=%-6d thiszc=%-6d 母线码=%4d | v0校验%s"
          % (tag, s["running"], s["duty"], s["newin"], s["zc"], s["erpm"], s["bemfTO"],
             s["desync"], s["old"], s["irq"], s["step"], s["ap"], s["va"], s["vb"],
             s["vc"], s["v0"], s["delta"], s["ci"], s["avg_int"], s["e_com"],
             s["lastzc"], s["thiszc"], s["bus"],
             "✓" if abs(s["v0"]-s["mean3"]) <= max(30, s["mean3"]//5) else
             ("✗(v0=%d 均值=%d ⇒ 采样落进关断期)" % (s["v0"], s["mean3"]))))

def show_f103(s, tag):
    if not s: print("  %s 读失败" % tag); return
    print("  %s state=%d throttle=%4d hold=%d | 遥测: eRPM_x100=%-6d 电压=%d 电流=%d ok=%d err=%d"
          % (tag, s["state"], s["throttle"], s["hold"], s["erpm_x100"], s["volts"],
             s["cur"], s["ok"], s["err"]))

mode = sys.argv[1] if len(sys.argv) > 1 else "burst"
if mode == "cycle":
    """开环专用：重复触发 N 轮开环运行（每轮约 8 秒）。
    为什么需要：开环版跑到 OL_RUN_LIMIT(8s) 就 ol_input_cur=0 锁存
    （OL_COOL_LIMIT=0 ⇒ 不自动重跑，"要再跑必须重新解锁"）⇒ 一轮只有 ~8 秒窗口。
    做法：先守零 → 把 F103 halt 800ms（DShot 掉信号 >0.5s ⇒ 电调自复位 + 重新解锁）
          → 恢复并等 1.5s（零油门下解锁）→ 放行（开环 8 秒）→ 再下一轮。
    注意：这个模式只适合【开环】版；闭环版用 run 模式（不会自己停）。"""
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    print("### 开环重复触发 %d 轮（每轮约 8 秒运行）" % n)
    for i in range(1, n + 1):
        relock()
        run(JL, ["-c", "init", "-c", "halt", "-c", "sleep 800",
                 "-c", "resume", "-c", "shutdown"])   # 掉信号 ⇒ 电调自复位（清开环锁存）
        # ★★ 不能拍脑袋定时等解锁！掉信号复位后，电调要重新识别输入 + 连续 1 秒零油门
        #    才能解锁 —— 定时短了就会"油门到得比解锁早"，电调永远不解锁（本项目的老坑）。
        #    所以这里直接读 armed，确认 =1 再放行。
        armed = None
        for k in range(12):                            # 最多约 6 秒
            time.sleep(0.5)
            armed = esc_read_u8(ESC_ARMED)
            if armed == 1:
                break
        volts = esc_read_u16(ESC_VOLTS)
        print("  第 %d/%d 轮：armed=%s  母线=%s  （等了 %.1f 秒）"
              % (i, n, armed, volts, (k + 1) * 0.5))
        if armed != 1:
            print("     ⚠ 还没解锁 ⇒ 跳过本轮（别放行，放了也没用）")
            continue
        release()
        print("     → 已放行（开环约 8 秒）")
        time.sleep(9.0)
    relock(); print("  → 已锁回")
    raise SystemExit(0)

if mode == "run":
    """持续放行 N 秒：全程【不采样、不 halt】—— 采集时的 halt 会让 PWM 冻住几十毫秒，
    会污染示波器波形，所以这个模式一次都不碰调试口。给"上示波器看相电压"用。"""
    secs = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    print("### 持续放行 %d 秒（不采样、不 halt）" % secs)
    show_f103(f103_read(), "F103 基线")
    release(); print("--- 已在跑，请看波形 ---")
    try:
        for i in range(secs):
            time.sleep(1)
            if (i + 1) % 15 == 0:
                print("   已跑 %d 秒" % (i + 1))
    finally:
        relock(); print("  → 已锁回")
    show_f103(f103_read(), "F103 末态")
    raise SystemExit(0)

if mode == "live":
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    itv = int(sys.argv[3]) if len(sys.argv) > 3 else 300
    print("### live 模式：%d 次快照，间隔 %dms（放行后单会话边跑边采）" % (n, itv))
    show_f103(f103_read(), "F103 基线")
    release(); print("--- 放行 ---")
    try:
        live(n, itv)
    finally:
        relock(); print("  → 已锁回")
    show_f103(f103_read(), "F103 末态")
    raise SystemExit(0)

if mode == "lock":
    relock(); print("已锁回 (hold_zero=1)"); raise SystemExit(0)

n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
hyst = int(sys.argv[3]) if len(sys.argv) > 3 else None
pol = int(sys.argv[4]) if len(sys.argv) > 4 else None
if hyst is not None:
    set_knobs(hyst, pol if pol is not None else 0)
print("### 闭环测试：%d 次采样%s" % (n, "" if hyst is None else "（hyst=%d pol=%d）" % (hyst, pol)))
show_f103(f103_read(), "F103 基线")
prev = esc_read()
show(prev, "放行前")
release()
print("--- 放行 ---")
t0 = time.time(); last = None
try:
    for i in range(1, n + 1):
        if time.time() - t0 > DRIVE_MAX_S:
            print("  (到时上限，收工)"); break
        time.sleep(0.45); last = esc_read(); show(last, "放行%-2d" % i)
        if i % 3 == 0:   # 每 3 次采一次 F103，读电调自报的 eRPM（单位"100 eRPM"）
            show_f103(f103_read(), "  ↳电调自报")
finally:
    relock(); print("  → 已锁回")
show_f103(f103_read(), "F103 末态")
show(esc_read(), "锁回后")
if prev and last:
    print("--- 汇总 --- eRPM %d→%d（峰值看上面各行），desync 变化 %d，bemfTO 变化 %d"
          % (prev["erpm"], last["erpm"], last["desync"] - prev["desync"],
             last["bemfTO"] - prev["bemfTO"]))
