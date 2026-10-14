# rm2027-drone · RM2027 无人机项目

> **定位**：RM2027 赛季无人机（蜂群 / 空中机器人方向）的**认知地基 + 飞控与电调的实现工程**。
> **起点**：2026-08-28（认知梳理）· **转入硬件实现**：2026-09-18 起 · **最近更新**：2026-10-04
>
> **现状一句话**：飞控（PX4 自研板级 + 双 IMU 驱动）与电调（AM32 自研 G071 目标 + 软件过零）
> **都已能在本板上编译运行**；电调功率级仍在台架调试。

---

## ★★ 代码分散在【三处】—— 先看这张图

**PX4 与 AM32 是第三方开源项目（AM32 是 GPL-3.0），必须各自 fork，以保留上游历史与许可。**
**本仓只放"我们自己写的"：文档 / 原理图 / 测试固件 / 工具。**

```
┌─────────────────────────────────────────────────────────────────────┐
│ ① 本仓（你在看的这个）   Gitee: AdoreElysia/by_agent                   │
│      = 文档 + 原理图 + 测试固件 + 工具                                  │
│      git clone https://gitee.com/AdoreElysia/by_agent.git             │
│                                                                     │
│ ② PX4 飞控改动           GitHub: AdoreElysia/PX4-Autopilot-rm2027      │
│      分支 h104-protocol（36 个 commit）                                │
│      git clone -b h104-protocol \                                    │
│          https://github.com/AdoreElysia/PX4-Autopilot-rm2027.git       │
│                                                                     │
│ ③ AM32 电调改动          GitHub: <待建 fork>（上游 am32-firmware/AM32） │
│      分支 main（1 个 commit / 6 个文件 / +261 −4）                     │
│      git clone -b main <你的 fork URL>                                │
└─────────────────────────────────────────────────────────────────────┘
```

**⇒ 为什么分三处**（不是"看起来操蛋"，是标准做法）：
```
· PX4 / AM32 有各自许可与上游 ⇒ 只能 fork，不能塞进本仓（否则许可混杂 + 以后没法 merge 上游）
· 本仓是【我们自己的产出】⇒ 独立，随便改
```

---

## 一、目录结构

```
rm2027-drone/
├── README.md                     ← 本文件
├── what_i_do.md                  ← 我（AI 侧）做过什么的总账
│
├── work/                         ★ 全部工作产出（294 个被跟踪文件）
│   ├── px4-code-twin/            ★ PX4 代码孪生文档（51 篇 / 约 25600 行）
│   │   ├── 01_extracted/         ← 提炼知识：CMake / Make / uORB / C 宏 / 启动汇编 语法
│   │   ├── 02_code_twin/         ← 代码孪生：每个源文件一篇（含「标注源码」）
│   │   ├── 03_moc/               ← 入口：按【构建/执行顺序】组织的 5 篇
│   │   ├── 04_notes/             ← 语法盲点审计
│   │   └── tools/                ← 文档维护脚本（链接/锚点/自审）
│   ├── ESC-*.md                  ← 电调：引脚映射 / 测量地图 / bootloader 根因 / DShot CRC …
│   ├── PX4*.md                   ← 飞控：索引与纪律 / rcS 时序 / bootloader 时序 / 复刻待办
│   ├── review-01…06-*.md         ← 手册对照 / 三问核查 / H104 提频 / 加计异常 / 协处理器 / 论文调研
│   └── esc-artifacts/            ← AM32 patch + 固件 bin + eeprom 备份
│
├── docs/                         认知与交接文档（7 篇）
│   ├── 01-网站认知.md · 02-认知网络-蜂群无人机.md
│   ├── 03-实现路径-无人机.md · 04-现有水平评估-rm2027代码.md
│   └── 交接-*.md · 日志.md · 硬件需求-给硬件组-v1.md
│
├── references/                   一手资料（约 33 MB / 28 个文件）
│   ├── 硬件手册/                 器件手册 + 文本提取
│   └── *.pdf                     ★ 2 份原理图（飞控板 + 电调板，团队产出，不可再得）
│
├── test_esc/                     F103 DShot 测试信号发生器（★ 见「已知问题」）
├── learning/                     L00–L08 学习课程（22 个文件）
├── firmware/                     固件相关（21 个文件 / 756 KB）
├── drone_code/                   飞控/电调代码片段（6 个文件）
└── archive/                      归档（3 个文件）
```

---

## 二、各部分是什么

| 目录 | 是什么 | 入口 |
|---|---|---|
| **`work/px4-code-twin/`** | **PX4 的"代码孪生"文档** —— 按 RM_note 的四层架构（`01_extracted` 提炼知识 / `02_code_twin` 代码孪生 / `03_moc` 执行序入口 / `04_notes` 经验）。**每个行号都可点，直接跳到孪生篇里的那段代码** | [`work/px4-code-twin/README.md`](work/px4-code-twin/README.md) |
| **`work/ESC-*.md`** | 电调（AM32 改造）全过程 | `work/ESC-引脚映射-已核对.md` |
| **`work/PX4*.md`** | 飞控：改造索引与**纪律**（踩坑结论） | `work/PX4改造-索引与纪律.md` |
| **`work/review-*.md`** | 六份审查报告 | — |
| **`docs/`** | 赛季初认知梳理 + 交接 | `docs/03-实现路径-无人机.md` |
| **`references/`** | **一手资料**：原理图、器件手册及文本提取 | `references/硬件手册/硬件手册索引与关键参数.md` |
| **`test_esc/`** | **F103 电调测试信号发生器**（分层 `Bsp`/`Module`/`App`）：发 DShot + 收 KISS 遥测 + 采电流模拟量，脱离飞控单独测电调 | `test_esc/README.md`（含接线表） |
| `learning/` | L00–L08 课程（做中学） | `learning/README.md` |

---

## 三、当前进度（2026-10-04）

| 线 | 状态 |
|---|---|
| **飞控：板级移植** | ✅ 编得出固件（`boards/rm2027/fmu-h743/`，25 个文件） |
| **飞控：驱动** | ✅ 自研 `hxy42688p`（华轩阳 ICM-42688P）+ `h104_imu`（HiPNUC HI04M0）+ IST8310 + SPA06 |
| **飞控：标定** | 🟡 六面标定 4/6（卡在 `invalid orientation`，已定位到 chip Y 通道增益异常并修） |
| **飞控：PX4 改动** | ✅ 36 个 commit（`h104-protocol`）= **43 个纯新增文件 + 1 个官方文件改 4 行** |
| **电调：AM32 改造** | ✅ 新增 `RM2027_ESC_G071` 目标 + **软件过零检测**（ADC-BEMF）替代物理比较器 |
| **电调：软件链路** | ✅ 全部打通（DShot 协议 / CRC / 换相 / 占空比 44%；`newinput=400` 精确解出） |
| **电调：功率级** | 🟡 **台架调试中**（怀疑 6.5V 驱动供电或测量方法 —— 见测量地图） |
| **电调：测试台** | ✅ `test_esc/`（F103）三方链路：发 DShot + 收 KISS 遥测（USART1 RX/PA10）+ 采电流模拟量（ADC1_IN1/PA1），2026-10-06 补 |
| **文档** | ✅ `work/` 25 篇 + `work/px4-code-twin/` 51 篇 |

---

## 四、赛季方向与关键结论（2026-08-28 建立，仍然有效）

1. **新赛季方向（已确认）**：官方 RM2027 规则亮点（2026-08-14）发布，空中机器人从"大尺寸空中火力平台"
   改为 **小型空间智能机器人** —— **重量 150–249 g、直径 60–140 mm、每局 4 架、机库（≤300×300×200 mm）部署、
   单次续航 ≤30 s、取消安全绳、全包围桨保**；任务 = 撞击造成 42 mm 级伤害 / 拦截飞镖弹丸 / 悬停侦察回传。
   → **不再适用旧"14–18 kg 大载重云台机"路线。**
2. **技术主线**：场内无 GPS ⇒ **UWB 场边定位**（ZJU 高飞 Fast-Lab 已验证，Nooploop LinkTrack）；
   飞控走 **PX4 小飞控 + 外部位置估计**；机库充电 / 起降引导 / 通讯网关是电控的"另一半主场"。
3. **开源标杆**：**Fast-Drone-250**（250 g 全自主开源，新规尺度基准）+ **EGO-Swarm**（UWB 集群协同）
   + PX4 / ArduPilot / Betaflight。
4. **团队水平**：嵌入式 / 通信 / 电机 / 裁判 / 工程化中上；新规缺口集中在 UWB 定位、自主飞行、
   PX4 SITL 仿真、机库充电、微型动力、撞击 / 拦截验证。
5. **仿真建议**：**必须做且是第一优先级** —— PX4 SITL + Gazebo 先跑通"起飞–任务–回库–充电"循环；
   撞击 / 拦截先动力学仿真验证可行性，避免造完发现物理做不到。

---

## 五、怎么开始（给学弟 / 队友）

```bash
# ① 本仓（文档 + 原理图 + 测试固件）
git clone https://gitee.com/AdoreElysia/by_agent.git

# ② 要动飞控 → 拉 PX4 那条分支
git clone -b h104-protocol https://github.com/AdoreElysia/PX4-Autopilot-rm2027.git

# ③ 要动电调 → 拉 AM32 的 fork（<待建>）；或直接用上游 + 打 patch
#    patch 在 ① 的 work/esc-artifacts/ 里
```

**★ 建议阅读顺序**（先建立"程序运行时"的视角）：
```
docs/03-实现路径-无人机.md                              ← 为什么这么造
work/px4-code-twin/03_moc/01-poweron-walkthrough.md      ← ★ 上电到飞行的执行主线
work/PX4改造-索引与纪律.md                               ← 踩过的坑（纪律）
work/ESC-引脚映射-已核对.md + ESC-测量地图与预期电压.md    ← 电调台架怎么量
```

---

## 六、⚠️ 已知问题（待修）

| # | 问题 | 影响 |
|---|---|---|
| ~~1~~ | ✅ **已修**：`test_esc/` 原来是「孤儿 gitlink」（独立仓 16 commit，主仓无 `.gitmodules`）| 已用 `git subtree` 并入主仓（**16 个 commit 历史完整保留**）⇒ 学弟 clone 一次即得 104 个文件 |
| **2** | PX4 的 `h104-protocol` 尚未推到 fork | 36 个 commit / 约 1.2 MB 待推 |
| **3** | AM32 尚未 fork | 那 1 个 commit 目前只在本地 |

---

## 六·补 · 体积说明（**这些是【有意保留】的，别删**）

仓库 clone 下来约 138 M，其中大头是**有意保留**的内容：

| 目录 | 体积 | 为什么保留 |
|---|---|---|
| `ai-session-log/` | **53 M** | ★ **AI 会话记录（4 个 zip）—— 用户明确说「有用，不要删」**。它占了大半体积、clone 会慢，但**不要**为了瘦身删除它或改写历史 |
| `references/` | 38 M | 器件手册 + **2 份原理图**（团队产出，不可再得） |
| `work/` | 5.9 M | 全部文档（含 `px4-code-twin/` 56 篇） |
| `test_esc/` | 4.4 M | F103 DShot 测试固件（含 16 个 commit 历史） |

> ⚠️ **给维护者**：若想减少 clone 体积，**先问过用户**。
> 已知的候选（重复的 `(1)` 文件、可重下的大 PDF）也**都已确认保留**。

---

## 七、约定（写代码 / 写文档前先看）

| 约定 | 说明 |
|---|---|
| **提交粒度** | **一个 commit 只做一件事**，消息写清"为什么"（便于逐条回看） |
| **行号可点** | 文档里的 `文件:行` 都做成**站内跳转**（跳到孪生篇里的代码，不用翻源码树） |
| **路径只维护一处** | 源码根只写在 `work/px4-code-twin/tools/source-root.conf` |
| **跨端行尾** | Linux 侧脚本必须 LF（CRLF 会 `bad interpreter`，且报错不提行尾） |
| **纪律登记处** | 踩过的坑都记在 `work/PX4改造-索引与纪律.md`，新坑往里加 |
| **文档分层** | 语法/机制 → `01_extracted`；某个文件的行号 → `02_code_twin`；流程 → `03_moc` |

---

## 八、来源与致谢

```
· PX4-Autopilot    https://github.com/PX4/PX4-Autopilot       （BSD-3）
· AM32             https://github.com/am32-firmware/AM32      （GPL-3.0）
· 文档结构参考       RM_note/rm-electric-knowledge-base（四层架构：raw / extracted / code_twin / moc）
```

## 九、相关外部资源

| 资源 | 位置 |
|------|------|
| 现有机器人框架 | `mas_embedded_threadx`（RM2027 赛季底盘/哨兵代码） |
| RM 培训/调研 | `projects/competition/rm2027-training/` |
| 个人 RM 待办（Obsidian） | `memory/obsidian/持续任务/rm代办.md` |
