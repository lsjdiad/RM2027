#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
H104（HiPNUC 超核电子）串口二进制协议 —— 离线解析 / 校验工具

依据：references/硬件手册/hipnuc_超核_指令与编程手册.md
      §串口二进制协议（帧格式 / HI91 / HI83 / CRC）

用法：
  python3 h104_parse.py --selftest                 # 用手册示例帧做自检（必须全绿）
  python3 h104_parse.py -f capture.bin             # 解析原始二进制抓包
  python3 h104_parse.py -f cap.txt --hex           # 解析十六进制文本抓包
  python3 h104_parse.py -f capture.bin --stats     # 统计特征（含 SOF 假设检验）
  python3 h104_parse.py -f capture.bin --json      # 输出机器可读结果

本文件刻意不依赖任何第三方库。
"""

import argparse
import json
import math
import re
import struct
import sys
from collections import Counter

SOF = b"\x5a\xa5"
CRC_POLY = 0x1021
MAX_PAYLOAD = 512

# 手册 §帧解析示例（HI91）给出的完整 82 字节报文，作为黄金测试向量
MANUAL_HI91_EXAMPLE = (
    "5A A5 4C 00 14 BB 91 08 15 23 09 A2 C4 47 08 15 1C 00 CC E8 61 BE "
    "9A 35 56 3E 65 EA 72 3F 31 D0 7C BD 75 DD C5 BB 6B D7 24 BC 89 88 "
    "FC 40 01 00 6A 41 AB 2A 70 C2 96 D4 50 41 ED 03 43 41 41 F4 F4 C2 "
    "CC CA F8 BE 73 6A 19 BE F0 00 1C 3D 8D 37 5C 3F"
)

# 手册 §帧解析示例 表里给出的解析值（用于自检）
MANUAL_EXPECT = {
    "tag": 0x91,
    "main_status": 0x1508,
    "temperature": 35,
    "air_pressure": 100676,      # Pa（float 精确值 100676.07）
    "system_time": 1840392,      # ms
    "acc_b": (-0.2206, 0.2092, 0.9489),
    "gyr_b": (-0.0617, -0.0060, -0.0101),
    "mag_b": (7.892, 14.625, -60.042),
    "roll": 13.052, "pitch": 12.188, "yaw": -122.477,
    "quat": (-0.4859, -0.1498, 0.0381, 0.8602),
}


def crc16_xmodem(data: bytes) -> int:
    """CRC-16/XMODEM：poly 0x1021，初值 0x0000，无输入/输出反转，无最终异或。"""
    crc = 0x0000
    for b in data:
        crc ^= (b << 8) & 0xFFFF
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ CRC_POLY) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


# ---------------------------------------------------------------- HI91
# 数据域固定 76 字节（手册 §浮点型数据帧（HI91））
HI91_TAG = 0x91
HI91_PAYLOAD_LEN = 76


def decode_hi91(p: bytes) -> dict:
    """解析 76 字节 HI91 数据域。所有多字节量小端。"""
    assert len(p) == HI91_PAYLOAD_LEN, len(p)
    d = {
        "tag": p[0],
        "main_status": int.from_bytes(p[1:3], "little"),
        "temperature_c": struct.unpack_from("<b", p, 3)[0],
        "air_pressure_pa": struct.unpack_from("<f", p, 4)[0],
        "system_time_ms": int.from_bytes(p[8:12], "little"),
        # 单位：G / deg/s / uT —— 载体系(b 系)
        "acc_b_g": list(struct.unpack_from("<3f", p, 12)),
        "gyr_b_dps": list(struct.unpack_from("<3f", p, 24)),
        "mag_b_ut": list(struct.unpack_from("<3f", p, 36)),
        "roll_deg": struct.unpack_from("<f", p, 48)[0],
        "pitch_deg": struct.unpack_from("<f", p, 52)[0],
        "yaw_deg": struct.unpack_from("<f", p, 56)[0],
        "quat_wxyz": list(struct.unpack_from("<4f", p, 60)),
    }
    return d


# MAIN_STATUS 位（手册 §MAIN_STATUS 状态字）——=1 表示“未收敛/未同步/异常”
MAIN_STATUS_BITS = {
    3: ("WB_CONV", "陀螺零偏未收敛"),
    4: ("MAG_DIST", "磁场状态异常(9轴)"),
    5: ("ACC_SAT", "加速度饱和(近2s内)"),
    6: ("GYR_SAT", "陀螺饱和(近2s内)"),
    7: ("ATT_CONV", "姿态未充分收敛"),
    9: ("STATIC", "判定为静止"),
    10: ("MAG_AIDING", "磁辅助使能(9轴)"),
    11: ("UTC_UNSYNC", "UTC 未同步(system_time 是本地ms)"),
    12: ("SOUT_PULSE", "本帧对应一次 SOUT 脉冲"),
}


def decode_main_status(v: int) -> list:
    return [name for bit, (name, _) in sorted(MAIN_STATUS_BITS.items()) if v & (1 << bit)]


# ---------------------------------------------------------------- 组帧
def iter_frames(buf: bytes):
    """
    从字节流里扫帧。返回 (frames, errors)。
    frames: [{'off':..,'crc':..,'calc':..,'ok':bool,'payload':bytes,'decoded':dict}]
    errors: [{'off':..,'reason':..}]
    只认 SOF=5A A5 且 LEN 合法的帧；CRC 校验失败也记下来（坏帧计数要用）。
    """
    frames, errors = [], []
    i, n = 0, len(buf)
    while i + 6 <= n:
        if buf[i:i + 2] != SOF:
            i += 1
            continue
        ln = int.from_bytes(buf[i + 2:i + 4], "little")
        if ln < 1 or ln > MAX_PAYLOAD:
            errors.append({"off": i, "reason": "LEN out of range (%d)" % ln})
            i += 1
            continue
        total = 6 + ln
        if i + total > n:
            errors.append({"off": i, "reason": "truncated frame (need %d, have %d)" % (total, n - i)})
            break
        crc_rx = int.from_bytes(buf[i + 4:i + 6], "little")
        calc = crc16_xmodem(buf[i:i + 4] + buf[i + 6:i + total])
        payload = buf[i + 6:i + total]
        fr = {"off": i, "len": ln, "crc": crc_rx, "crc_calc": calc,
              "ok": crc_rx == calc, "payload": payload, "decoded": None}
        if ln == HI91_PAYLOAD_LEN and payload[0] == HI91_TAG:
            fr["decoded"] = decode_hi91(payload)
        frames.append(fr)
        i += total
    return frames, errors


# ---------------------------------------------------------------- 统计
def stream_stats(buf: bytes) -> dict:
    n = len(buf)
    c = Counter(buf)
    st = {
        "n_bytes": n,
        "byte_5a_count": c[0x5A],
        "byte_a5_count": c[0xA5],
        "sof_5aa5_count": sum(1 for i in range(n - 1) if buf[i] == 0x5A and buf[i + 1] == 0xA5),
        "top_bytes": [(hex(k), v) for k, v in c.most_common(12)],
    }
    pos = [i for i, b in enumerate(buf) if b == 0x5A]
    gaps = [pos[i + 1] - pos[i] for i in range(len(pos) - 1)]
    st["gap_5a_histogram"] = sorted(Counter(gaps).items())
    # 假设 SOF=5A A5 且一帧 82 字节时，0x5A 的期望密度
    st["expected_5a_if_hi91"] = n / 82.0
    st["observed_over_expected"] = (c[0x5A] / (n / 82.0)) if n else None
    return st


# ---------------------------------------------------------------- 自检
def selftest(verbose=True) -> bool:
    raw = bytes.fromhex(MANUAL_HI91_EXAMPLE)
    ok = True
    def chk(name, got, want, tol=0.0):
        nonlocal ok
        good = (abs(got - want) <= tol) if isinstance(want, float) else (got == want)
        ok = ok and good
        if verbose:
            print("  %-22s got=%-16s want=%-16s %s" % (name, got, want, "OK" if good else "*** FAIL ***"))
        return good

    if verbose:
        print("== 手册示例帧结构 ==")
    chk("total_bytes", len(raw), 82)
    chk("sof", raw[:2].hex(" ").upper(), "5A A5")
    chk("len_field", int.from_bytes(raw[2:4], "little"), 76)
    chk("payload_bytes", len(raw[6:]), 76)

    if verbose:
        print("== CRC-16/XMODEM ==")
    calc = crc16_xmodem(raw[:4] + raw[6:])
    chk("crc_calc", hex(calc), hex(int.from_bytes(raw[4:6], "little")))

    frames, errs = iter_frames(raw)
    chk("frames_found", len(frames), 1)
    if verbose:
        print("== HI91 字段（对手册标注解析值）==")
    d = frames[0]["decoded"]
    chk("tag", d["tag"], MANUAL_EXPECT["tag"])
    chk("main_status", d["main_status"], MANUAL_EXPECT["main_status"])
    chk("temperature_c", d["temperature_c"], MANUAL_EXPECT["temperature"])
    chk("air_pressure_pa", round(d["air_pressure_pa"]), MANUAL_EXPECT["air_pressure"])
    chk("system_time_ms", d["system_time_ms"], MANUAL_EXPECT["system_time"])
    vec_map = {"acc_b_g": "acc_b", "gyr_b_dps": "gyr_b", "mag_b_ut": "mag_b", "quat_wxyz": "quat"}
    for k, ek in vec_map.items():
        for got, want in zip(d[k], MANUAL_EXPECT[ek]):
            chk("%s" % k, round(got, 4 if k != "mag_b_ut" else 3), want, tol=1e-3)
    for k in ("roll_deg", "pitch_deg", "yaw_deg"):
        chk(k, round(d[k], 3), MANUAL_EXPECT[k.split("_")[0]], tol=1e-3)

    if verbose:
        print("\n结果：", "全部通过 ✅" if ok else "有 FAIL ❌")
    return ok


# ---------------------------------------------------------------- IO
def load_bytes(path: str, is_hex: bool) -> bytes:
    blob = open(path, "rb").read()
    if is_hex or re.fullmatch(rb"[\s0-9A-Fa-f]*", blob) and b" " in blob[:200]:
        txt = blob.decode("utf-8", "replace")
        toks = re.findall(r"[0-9A-Fa-f]{2}", txt)
        return bytes(int(t, 16) for t in toks)
    return blob


def main():
    ap = argparse.ArgumentParser(description="H104 (HiPNUC) HI91/HI83 离线解析工具")
    ap.add_argument("--selftest", action="store_true", help="用手册示例帧自检")
    ap.add_argument("-f", "--file", help="抓包文件（原始二进制或十六进制文本）")
    ap.add_argument("--hex", action="store_true", help="文件是十六进制文本")
    ap.add_argument("--stats", action="store_true", help="输出流统计特征")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--max-print", type=int, default=5, help="最多打印几帧明细")
    a = ap.parse_args()

    if a.selftest:
        sys.exit(0 if selftest() else 1)

    if not a.file:
        ap.print_help()
        sys.exit(2)

    buf = load_bytes(a.file, a.hex)
    frames, errs = iter_frames(buf)
    good = [f for f in frames if f["ok"]]
    bad = [f for f in frames if not f["ok"]]
    dec = [f for f in good if f["decoded"]]

    out = {
        "n_bytes": len(buf),
        "frames": len(frames),
        "frames_crc_ok": len(good),
        "frames_crc_bad": len(bad),
        "frames_hi91": len(dec),
        "scan_errors": errs[:20],
    }
    # 帧率估算：用首末帧的 system_time（ms）
    if len(dec) >= 2 and dec[-1]["decoded"]["system_time_ms"] != dec[0]["decoded"]["system_time_ms"]:
        dt = (dec[-1]["decoded"]["system_time_ms"] - dec[0]["decoded"]["system_time_ms"]) / 1000.0
        out["odr_hz_est"] = (len(dec) - 1) / dt if dt > 0 else None

    if a.json:
        out["frames_detail"] = [
            {"off": f["off"], **{k: v for k, v in f["decoded"].items() if k != "tag"}} for f in dec[:a.max_print]
        ]
        if a.stats:
            out["stats"] = stream_stats(buf)
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    print("字节数        : %d" % out["n_bytes"])
    print("扫到帧        : %d（CRC 好 %d / 坏 %d）" % (out["frames"], out["frames_crc_ok"], out["frames_crc_bad"]))
    print("其中 HI91 帧  : %d" % out["frames_hi91"])
    if "odr_hz_est" in out:
        print("帧率估算      : %.1f Hz（按 system_time）" % out["odr_hz_est"])
    if errs:
        print("扫描告警      : %s" % errs[:5])

    for f in dec[:a.max_print]:
        d = f["decoded"]
        print("\n--- 帧 @%d  len=%d  CRC=0x%04X ---" % (f["off"], f["len"], f["crc"]))
        print("  main_status  : 0x%04X  %s" % (d["main_status"], ",".join(decode_main_status(d["main_status"])) or "-"))
        print("  temperature  : %d °C" % d["temperature_c"])
        print("  air_pressure : %.1f Pa" % d["air_pressure_pa"])
        print("  system_time  : %d ms" % d["system_time_ms"])
        print("  acc_b  [G]   : %s" % ["%.4f" % x for x in d["acc_b_g"]])
        print("  gyr_b  [dps] : %s" % ["%.4f" % x for x in d["gyr_b_dps"]])
        print("  mag_b  [uT]  : %s" % ["%.4f" % x for x in d["mag_b_ut"]])
        print("  rpy    [deg] : %.3f / %.3f / %.3f" % (d["roll_deg"], d["pitch_deg"], d["yaw_deg"]))
        print("  quat wxyz    : %s" % ["%.5f" % x for x in d["quat_wxyz"]])

    if a.stats or not frames:
        print("\n=== 流统计 / SOF 假设检验 ===")
        s = stream_stats(buf)
        for k in ("n_bytes", "byte_5a_count", "byte_a5_count", "sof_5aa5_count",
                  "expected_5a_if_hi91", "observed_over_expected"):
            print("  %-24s %s" % (k, s[k]))
        print("  %-24s %s" % ("top_bytes", s["top_bytes"]))
        print("  %-24s %s" % ("gap_5a_histogram", s["gap_5a_histogram"]))


if __name__ == "__main__":
    main()
