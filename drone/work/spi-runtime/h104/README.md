# H104（HiPNUC HI04M0）协议 / 抓包 / 驱动验证

> 目录：`work/spi-runtime/h104/`　｜　建立：2026-09-30　｜　最后更新：2026-09-30（驱动上板验证通过）
> 上级入口：`work/spi-runtime/README.md`　｜　规格正本：`../H104-帧格式规格.md`

## ★ 一键回归（先跑这个，再考虑上板）

```bash
work/spi-runtime/h104/run-regression.sh      # 三层：Python 自检 + 判决器 + C++ 解析器，全绿才过
```

## 上板取证

```bash
work/spi-runtime/h104/h104-dump-console.sh 4   # 复位→停在自检行→整块 dump console 并 grep
work/spi-runtime/h104/h104-dump.sh             # 抓原始字节流（h104cap 工具用）
```

**驱动本体不在这里**，在 PX4 分支 `h104-protocol`：`src/drivers/imu/hipnuc_h104/`。

---

## 文件

| 文件 | 说明 |
|---|---|
| **`run-regression.sh`** | ★ **一键离线回归**（三层，见上） |
| **`h104-driver-verify.log`** | ★ **驱动上板验证取证**（自检行 + 旁证 + 两个新坑） |
| `h104-dump-console.sh` | 上板取证脚本（整块 console dump，绕开 QGC 抽干未读窗口的问题） |
| `h104_verify.py` | **上板抓包判决器**：组帧 / 偏移平移扫描 / 物理自检 / 姿态自洽 |
| `h104_parse.py` | 离线解析 / 校验工具（HI91 逐字段、CRC、组帧、流统计）。零依赖 |
| **`h104-cap.bin`** | ★ **真实抓包 8192 B = 98 帧 0 坏**（驱动的黄金回归向量） |
| `h104-verify.log` / `h104-crosscheck.log` / `h104-real-capture-analysis.log` | 上板验证日志 |
| `h104-report.print.txt` | 模块自报 `LOG VERSION/COMCONFIG/USRCONFIG` 原文 |
| `h104-dump.sh` | 用 SWD dump `h104cap` 写进固定 RAM 的报告/字节流 |
| `h104-selftest.log` | `h104_parse.py --selftest`：手册示例帧自检 23/23 通过 |
| `capture-2026-09-29-lossy.hex` + `h104-lossy-capture-analysis.log` | **作废的旧抓包**（SWD 轮询混叠），反面教材 |
| `code-draft/h104cap/` | 抓包工具源码（**规范位置已移到 PX4 分支 `h104-protocol`: `src/systemcmds/h104cap/`**） |
| `h104-lossy-capture-analysis.log` | 对该抓包的统计 —— 证明"`0x5A` 是帧头"不成立 |
| `code-draft/h104cap/` | **抓包工具草稿**（PX4 systemcmd）。**未编译、未上板**；落码步骤见 `../H104-完整帧抓取方案.md` §3 |

---

## 用法

```bash
# 1) 自检：用手册自带的 82 字节示例帧验证 CRC 与全部字段（应当全绿、退出码 0）
python3 h104_parse.py --selftest

# 2) 解一份真实抓包（原始二进制）
python3 h104_parse.py -f h104-cap.bin --stats     # 统计 + SOF 假设检验
python3 h104_parse.py -f h104-cap.bin             # 打印前 5 帧逐字段明细
python3 h104_parse.py -f h104-cap.bin --json      # 机器可读

# 3) 解十六进制文本抓包
python3 h104_parse.py -f capture-2026-09-29-lossy.hex --hex --stats
```

**判据**（详见 `../H104-完整帧抓取方案.md` §6）：`frames_crc_bad = 0`、`odr_hz_est ≈ 100 Hz`、
静止时 `acc_b` 合成 ≈ 1.0 G、`gyr_b` ≈ 0。

---

## 抓包工具草稿（`code-draft/h104cap/`）

`h104cap.c` / `Kconfig` / `CMakeLists.txt` → 放到 `PX4/src/systemcmds/h104cap/`，
板级配置加 `CONFIG_SYSTEMCMDS_H104CAP=y`。子命令：

```sh
h104cap capture -b 115200 -s 3      # 抓进固定 RAM 缓冲 g_h104_cap_buf + 打印统计
h104cap cmd "LOG VERSION"           # 发 ASCII 查询命令（TX=PB6）并回显应答
h104cap cmd "LOG COMCONFIG"
h104cap dump -n 512                 # hex dump 缓冲区到 console
```

**本期状态**：只做了**主机侧静态检查**，没有编译、没有上板：

- `gcc -fsyntax-only -Wall -Wextra`（配 stub 头）**通过**；
- 用同一个源文件在主机上跑通了黄金向量：`h104_crc16` 对 82 字节手册示例算出 **`0xBB14`**（与手册、与 Python 实现三边一致），
  `h104_scan()` 准确扫出 **1 帧、CRC 好、tag=0x91**；
- ⚠️ **未做的**：真编译、烧写、上板、`/dev/ttyS0` 实际读通 ⇒ **不要当成"能用"**。
