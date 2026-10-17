# review-06 · OmniRisk 调研：这套技术能不能借鉴到 RM2027

- 调研人：ominirisk-scout（**纯只读**：只经网络读取 arXiv / GitHub 镜像，未修改任何 PX4 源码、未碰硬件）
- 日期：2026-10-02
- 用户原话：> "代会去看一下 VANdexj/OminiRisk 这个 github / arxiv.org/abs/2609.18191 / 挂个队友去看看 / 看看这个技术有可能借鉴吗?"
- 用户后续补充：> "算了吧，说他用了很贵很重的设备才实现的"

---

## 出处引用约定（全文通用）

| 写法 | 含义 |
|---|---|
| `arXiv:2609.18191 §VI-D / Table III` | 论文小节号（比行号稳定，任何人可复核） |
| `README:126` | 仓库 `VANdexj/OmniRisk` 的 `README.md` 行号（`main` 分支，共 312 行） |
| `src:policy/network.py` | 仓库内源码文件（本文引用到的都已实际下载并读过） |
| `ghproxy` | 本机唯一可用的 GitHub 读取路径 `https://ghproxy.net/https://raw.githubusercontent.com/...` |

**三层标注**（本文每条结论都标）：

- **【实测】** = 本轮**真的取到了字节**并读过（HTTP 200 + 正文），或 shields.io 服务端回传的 GitHub 统计
- **【源码】** = 仓库源码原文（文件已下载，可复核）
- **【推理】** = 我明说的估算/推测，标注了估算方法

**⚠️ 本轮明确没查到的项**（不编）：见 §5。

---

## 0. 结论摘要（先看这三条）

### ★ 结论（三选一）：**不值得投入**

> **这套东西是"激光雷达 + Jetson Orin NX 伴生计算机"级别的方案（≈ 公斤级、数百美元~千美元级载荷），
> 与本项目"无 GPU、无伴生计算机、无 LiDAR、无 USB/无 SD"的硬约束正面冲突。
> 直接借鉴：不可能。可借的"思想"只有 1.5 条，而且不解决我们当前任何一个未决问题。
> ⇒ 判定：不值得投入（留档即可，不排期、不买硬件、不写代码）。**

**判据（三条，全部可复核）：**

| # | 判据 | 出处 | 层次 |
|---|---|---|---|
| 判据 1 | **平台是"重装备"**：Livox Mid-360 3D 激光雷达 + NVIDIA Jetson Orin NX 伴生计算机 + NxtPX4v2 飞控。**感知全靠 LiDAR，算力全在 Jetson 上**，PX4 只当底层控制器 | `README:118-133`、`arXiv §VI-A`、`arXiv Fig.4` | 【实测】 |
| 判据 2 | **它的输入我们造不出来**：网络输入是 `96×384×5` 张量 = 距离全景图(1) + 动态掩码(1) + 笛卡尔表面速度(3)，需要 **LiDAR 里程计(FAST-LIO2) + 运动目标检测(M-detector) + 匈牙利匹配跟踪** 三级前处理。论文自己说"range data alone cannot reveal lateral motion"——**光有距离还不够，必须有动目标跟踪器** | `arXiv §III-A3, §IV-A1, §IV-B`、`src:trt_transfer.py`（`H,W = 96,384`） | 【实测】+【源码】 |
| 判据 3 | **算力差 4~5 个数量级**：网络是 **两个 ResNet-18 主干 + 两个 1×1 卷积评分头**，实测在 Orin NX 上**推理 P95 20.0~20.5 ms、端到端 P95 42.2~45.8 ms**（预算 50 ms）。H743 无 NPU、1 MB RAM，**连一层的中间特征图都放不下** | `arXiv §VI-D, Table III`、`src:policy/models/backbone.py`、`src:policy/network.py` | 【实测】+【源码】+【推理】 |

**一句话给用户**：
> 论文本身是好工作（真机 15 m/s 连续规避、成功率 90.7%/86.7%），
> **它的"贵"和"重"不是缺点，是我们的约束** —— 它假设你有一台几百克~1 公斤、几十 W 的激光雷达和一台 Jetson。
> 我们这块板子**连它的输入都产生不了**，更谈不上跑它的网络。

---

## 1. 它是什么

### 1.1 仓库名先纠错 ★

**用户写的 `VANdexj/OminiRisk` 不存在**（`Omini` 是笔误）：

| 路径 | HTTP | 层次 |
|---|---|---|
| `.../VANdexj/OminiRisk/main/README.md` | **404** | 【实测】 |
| `.../VANdexj/OmniRisk/main/README.md` | **200**（11 548 B） | 【实测】 |

**⇒ 正确仓库是 `VANdexj/OmniRisk`**（论文摘要里给的链接也是这个：`https://github.com/VANdexj/OmniRisk`）。

### 1.2 GitHub 仓库 `VANdexj/OmniRisk`

| 项 | 值 | 出处 | 层次 |
|---|---|---|---|
| 用途 | 论文的官方实现：学习式全向轨迹风险规划器（ROS 规划节点 + CUDA 仿真器 + 数据集生成器） | `README:152-158` | 【实测】 |
| Star | **20** | shields.io `github/stars` → 服务端查 GitHub API | 【实测】 |
| Fork | **2** | shields.io `github/forks` | 【实测】 |
| 默认分支提交数 | **1**（即整仓库一次性入仓，不是渐进开发） | shields.io `commit-activity/t` | 【实测】 |
| 最近提交 | **September**（2026 年 9 月，与论文 9/16 投稿一致） | shields.io `last-commit` | 【实测】 |
| 主语言 | **C++ 85.6%**（仿真器/控制器/ROS 栈是 C++，网络是 Python） | shields.io `languages/top` | 【实测】 |
| Release | **v1.0**（含预训练权重 `omnirisk_epoch60.pth`） | shields.io `v/release`、`README:174-186` | 【实测】 |
| 许可证 | **MIT**（Copyright 2026 OmniRisk Authors + 2024 TJU-Aerial-Robotics） | `LICENSE`（HTTP 200，读了前 5 行）、`README:310-312` | 【实测】 |
| 依赖/环境 | Ubuntu 20.04 + ROS Noetic + CUDA；Jetson 侧 JetPack 5.1.x；`requirements.txt` 有 `opencv-python 4.11 / open3d 0.16 / numpy 1.22 / torch 生态` | `README:145`、`src:requirements.txt` | 【实测】 |
| 工程结构 | `OmniRisk/`(网络+训练+ROS节点) `Simulator/`(CUDA LiDAR 仿真器) `Controller/`(SO(3) 控制器) `ros_ws/`(FAST-LIO/M-detector/px4ctrl/EKF/Livox 驱动) `docker/` `scripts/` | `README:151-158` | 【实测】 |

**许可结论**：MIT ⇒ **法律上可以随便用**（商用也行，署名即可）。**拦我们的不是许可，是硬件。**

### 1.3 arXiv `2609.18191` —— 编号**真实存在**（已核实）

> **不要怀疑这个编号**：`2609` = 2026 年 9 月，与当前日期（2026-10-02）自洽。`web_fetch https://arxiv.org/abs/2609.18191` **HTTP 200**，正文完整取回。

| 项 | 值 | 层次 |
|---|---|---|
| 标题 | **OmniRisk: Omnidirectional Trajectory-Risk Learning for Agile Quadrotor Dynamic Avoidance** | 【实测】 |
| 分类 | cs.RO（Computer Science > Robotics） | 【实测】 |
| 作者 | Yifan He†, Yang Liu†, Wenhao Zhao†, Hai Lin, Deping Zhang, Mingze Ma, Xin Zhou, **Fei Gao**, Huan Yu\*, Zipeng Dai\*, Ziming Ding\*（†同等贡献，\*通讯） | 【实测】 |
| 单位 | **Differential Robotics**（杭州）+ **浙江大学** | 【实测】+`README:9` |
| 提交 | **v1: 2026-09-16**；**v2: 2026-09-20** | 【实测】 |
| 篇幅 | 8 pages, 5 figures, 6 tables | 【实测】 |
| 链接 | [abs](https://arxiv.org/abs/2609.18191) ｜ [HTML v2](https://arxiv.org/html/2609.18191v2) ｜ [PDF](https://arxiv.org/pdf/2609.18191) | 【实测】 |
| 许可 | arXiv perpetual non-exclusive license | 【实测】 |
| BibTeX | `@article{he2026omnirisk, ... journal={arXiv preprint arXiv:2609.18191}, year={2026}}` | `README:297-304` |

### 1.4 二者关系

**是"论文 = 仓库的实现"，一一对应。** 证据三条（全【实测】）：

1. 论文摘要末尾直接给了仓库链接：`Code is available at https://github.com/VANdexj/OmniRisk`；
2. 仓库 `README:12,16` 反向链回 `arxiv.org/abs/2609.18191`，BibTeX 条目标题与论文标题**逐字相同**；
3. 源码与论文公式能对上：`src:policy/network.py` 的 `OmniRiskNetwork` 就是论文 §V-C1 的"双分支循环卷积网络"（两路 backbone + 两个 head），`src:trt_transfer.py` 的 `H, W = cfg["image_height"], cfg["image_width"]  # 96, 384` 与输入张量的 `H×W` 一致。

---

## 2. 核心技术是什么（讲原理，不抄摘要）

### 2.1 解决什么问题

**敏捷四旋翼在全向范围内躲避高速运动的障碍物**（论文 Fig.1 的招牌场景：穿越石堆时躲开一颗横飞过来的球）。难点在论文 §I 说得很清楚：

- 反应窗口极短 ⇒ 规划器必须在控制周期内交出轨迹，**优化耗时不能随障碍物数量增长**；
- 主流做法两头堵：**完整时空约束的优化器**（SIMP 一类）随障碍数爆炸（论文 Table III 实测 |O|=6 时 P95 **2110.9 ms**，96.3% 周期超时）；**轻量局部精修**（FAPP 一类）够快（17 ms）但密集高速场景成功率崩到 **8%**。

**输入**：非重复扫描 LiDAR 点云流 + 里程计 + **已确认的动态障碍轨迹**（质心/速度/包围盒/ID）。
**输出**：一条**最小 jerk 五次多项式轨迹**（20 Hz 提交），交给 SO(3) 几何控制器以 50 Hz 跟踪。

### 2.2 关键方法（三个贡献，论文 §I 自己列的）

**(1) 固定维度的规划输入张量** —— 把"几何 + 运动"塞进同一个张量
`I_t = [D_t, M_t, V_t] ∈ R^{H×W×5}`（`H=96, W=384`）：
- `D_t`：**米制距离全景图**（球面投影，每格记录该方位最小距离，式(3)）；
- `M_t`：**二值动态掩码**（哪些回波属于动目标）；
- `V_t`：**笛卡尔表面速度通道**（动目标像素上填真实米制速度，其余为 0）。

> ★ 这一条是整个方法的**要害**：论文明确说"**稀疏的距离观测不能直接揭示障碍物的运动**"（§I），
> 所以必须由上游 M-detector 先把动目标分出来、跟踪出速度，再"画"进 `M_t`/`V_t`。
> **没有动目标跟踪器，这个张量就是缺三个通道的。**

**(2) 沿障碍物速度对齐的「非对称动态风险场」** —— 论文最可搬的一段数学
- 各向异性度量张量（式 7）：`A_o = σ⊥⁻²·I + (σ∥⁻² − σ⊥⁻²)·e_o e_oᵀ`，其中 `e_o` 是障碍速度方向单位向量、`σ∥` 随障碍速率增长 ⇒ **风险椭球沿运动方向拉长**（"提前看到危险，横向仍保持边界"）。
- 非对称因果门（式 8）：`r_o(q,v_rel) = φ_o(q) · softplus(α·v_relᵀ n_o)`，`φ_o(q)=exp(−qᵀA_o q)`。
  - `n_o` 是等风险椭球的内法向；`v_relᵀn_o > 0` 恰好等价于"距离正在缩小"。
  - ⇒ **接近中的风险被放大，远离的风险衰减到 0**。消融实验：去掉方向投影，A–R 方向准确率从 **96.2% 掉到 51.8%**，DCR（不必要规避率）从 **4.0% 涨到 34.0%**（Table II）。
- 沿候选轨迹做**有向路径积分**（式 9）得到轨迹级风险 ⇒ 提供**稠密、连续**的监督信号（规避"距离阈值产生阶跃标签、梯度几乎处处为零"的坑，§V-B1）。

**(3) 离线蒸馏：把在线优化换成一次前向** —— 论文的范式贡献
- **离线**：在特权仿真里随机采样遭遇，用**逆 CPA 采样**（先抽目标最近距离与时刻，再反推障碍初态）把样本堆在"快要撞上"的区域；用真值 ESDF + 真值轨迹算出 `J_s,i`（静态代价）与 `J_d,i`（动态风险），当作标签。
- **在线**：网络对**全向锚点格** `A` 上的全部候选基元**一次前向**打两个分（静态代价 + 动态风险），选 `argmin`，再**闭式**重建所选五次多项式。
- ⇒ **在线不再做风险积分** ⇒ **复杂度对障碍物数量是 O(1)**（候选数 `N=36` 固定，与 |O| 无关）。
- 关键设计：**头隔离**（§V-C2）——候选轨迹的**几何只由静态头生成**，`[M_t, V_t]` **不能改变轨迹形状**，只能影响打分。目的是抑制轨迹抖动。源码证实：`src:policy/network.py` 里 `endstate` 只由 `depth_feature`（+obs）产生，`dynamic_head` 只输出一个分数。

### 2.3 网络结构与推理开销

**结构（源码，可复核）**：

```
src:policy/network.py   OmniRiskNetwork(observation_dim=9, output_dim=10, hidden_state=64)
├── image_backbone  = StaticBackbone(64)              → ResNet18，conv1 输入 1 通道（depth）
├── dynamic_backbone= DynamicBackbone(64, in_ch=4)    → ResNet18，conv1 输入 4 通道（mask+vel 3）
├── static_head     = ScoreHead(64+9=73 → 10)         → 1×1 conv×3（256,256,10）
└── dynamic_head    = ScoreHead(64+64+9=137 → 1)      → 1×1 conv×3（256,256,1）
```
- 两个主干都是**完整 ResNet-18**（`src:policy/models/backbone.py` 直接 `resnet18(pretrained=False)`），只是把 `conv1` 换成 1/4 通道、`output_layer` 换成 1×1 卷积；
- 卷积沿**方位角做循环填充**（`_CircularConv2d`，用 `torch.cat` 手写以兼容 torch2trt）⇒ 360° 接缝连续；
- 输出：`endstate`(9 通道 = x/y/z 各 p,v,a) + `static_score`(1) + `dynamic_score`(1)，空间尺寸 `vertical_num×horizon_num = 3×12 = 36` 个基元（`src:config/traj_opt.yaml:horizon_num 12 / vertical_num 3`）。

**推理开销**：

| 指标 | 值 | 出处 | 层次 |
|---|---|---|---|
| 网络推理 P95 | **20.0 – 20.5 ms** | `arXiv §VI-D`、`README:74` | 【实测】 |
| 端到端规划 P95（含张量栅格化） | **42.2 – 45.8 ms**（|O|=1/4/6），最坏 50.9 ms，超时率 3.0% | `arXiv §VI-D Table III` | 【实测】 |
| 控制预算 | 50 ms（20 Hz 重规划），控制器 50 Hz 独立跟踪旧轨迹 | `arXiv §VI-A, §III-B2` | 【实测】 |
| 加速手段 | **TensorRT fp16**（`trt_transfer.py` 用 `torch2trt`，`fp16_mode=True`）；无 TensorRT 时走 PyTorch | `src:trt_transfer.py`、`README:236-245` | 【源码】 |
| 参数量 | **≈ 22 M**（两个 ResNet-18 各 ~11.2 M，两个 head ~0.2 M） | 由 `resnet18(pretrained=False)` 标准结构推算 | 【推理】 |
| 单次前向算力 | **≈ 2.7 GMAC（≈5.4 GFLOP）**：ResNet-18 在 224² 为 1.82 GMAC，按面积比 `96×384 / 224×224 = 0.735` 折算 ≈1.34 GMAC/主干 ×2 | 卷积网络 FLOPs 随输入面积线性缩放 | 【推理】 |

> **⚠️ 参数量/FLOPs 是我按标准 ResNet-18 结构估算的，论文和 README 都没给这两个数**，请当**量级参考**、不要当引用数字（见 §5）。

### 2.4 对输入数据的要求（★ 关键）

| 需求 | 内容 | 出处 |
|---|---|---|
| 传感器 | **360° 3D LiDAR**（Livox Mid-360，非重复扫描），仰角带 **−7° ~ +52°** | `README:125`、`src:config/traj_opt.yaml:lidar_elev_min_deg/-max_deg` |
| 里程计 | **FAST-LIO2**（LiDAR-惯导里程计，做运动补偿） | `arXiv §IV-A1`、`README:128` |
| 动目标检测 | **M-detector**（事件式点流检测器，从累积静态背景里分割运动回波） | `arXiv §IV-B`、`README:129` |
| 跟踪 | 匈牙利算法按质心欧氏距离关联，维护 `(c_o, v_o) ∈ R⁶` 六维状态；**轨迹需要"存活时窗 τ_track 内连续关联"才能确认** | `arXiv §IV-B` |
| 数据量/标注 | **不需要人工标注**。全部监督来自**特权仿真**（真值 ESDF + 真值轨迹 + 逆 CPA 采样），训练 200 epoch、batch 16、lr 1.5e-4（`src:train.py`） | `arXiv §III-B1`、`src:train.py` |
| 仿真器 | 自带 **CUDA LiDAR 仿真器**（`Simulator/sensor_simulator_cuda`）生成数据集 | `README:224-231` |
| 域对齐 | 5 个通道在仿真/真机之间保持**同一球面离散化、同一循环边界、同一背景累积窗**；训练时还对动态掩码注入**假阳/假阴腐蚀噪声**（`p_fp`/`p_fn`）以抗跟踪掉线 | `arXiv §IV-C1, §IV-C2` |

**⇒ 一句话：这套方法的"最低硬件门槛"是 `3D LiDAR + 能跑 ROS/CUDA 的伴生计算机`。二者缺一，方法连输入都构造不出来。**

---

## 3. ★ 能不能借鉴到我们的项目

### 3.1 逐条对照（我们的实际情况 vs 它的要求）

| 它的要求 | RM2027 现状 | 差距 |
|---|---|---|
| 360° 3D LiDAR | **没有**（传感器只有 `hxy42688p`、`h104_imu`、`ist8310`、`spa06`） | ❌ 致命：无法产生 `D_t/M_t/V_t` |
| LiDAR-惯导里程计 FAST-LIO2 | 无（也不需要，PX4 EKF2 已够） | ❌ |
| 动目标检测/跟踪（M-detector + 匈牙利） | 无 | ❌ |
| 伴生计算机（Ubuntu + ROS Noetic + CUDA） | **没有，且用户已明确"飞控不需要协处理器"**（`work/review-05-协处理器审计.md`） | ❌ 致命 |
| GPU/TensorRT fp16，20 ms 推理 | 无 GPU、无 NPU；H743 @480 MHz | ❌ 数量级差距（见下） |
| 20 Hz 重规划 + 50 ms 预算 | 飞控主循环能到 1 kHz，但那是**控制**不是**规划** | ⚠️ 时序不是瓶颈，算力才是 |
| 数据/训练 | 无 GPU ⇒ 无法训练（虽然 MIT 给了预训练权重） | ❌ |
| 数据回传（训练/调试需要大量数据） | **板上无 USB、无 microSD**，只能靠无线数传 | ⚠️ 雪上加霜 |

### 3.2 三种情况分别说明（任务要求）

#### (a) 能直接借鉴？ —— **不能。** 三条硬阻断，任意一条单独就足够否决

**阻断 1 · 感知**：它要 3D LiDAR，我们一个都没有。而且论文 §I/§IV-B 明说"**距离数据本身揭示不了横向运动**"，所以还得再加一整套动目标检测+跟踪。**这不是"改改输入通道"能绕过去的**，是整条感知链都不存在。

**阻断 2 · 算力**（【推理】，方法已写清）：
- 网络 ≈22 M 参数，fp16 权重就 **≈45 MB**、fp32 ≈90 MB；H743VIT6 是 **2 MB Flash / 1 MB RAM**（本板，常识级参数）⇒ **权重都装不下**；
- 中间特征图：`96×384×64` fp32 = **9.4 MB**，**一层就超过整块 RAM**；
- 算力：≈2.7 GMAC/次。Orin NX 实测 20 ms；Cortex-M7 无 NPU、无 SIMD int8 加速阵列，CMSIS-NN 量级 **~0.5 GMAC/s** ⇒ **单次推理 ~5 秒**，是 50 ms 预算的 **100 倍**，比 Orin NX 慢 **~250 倍**（按 20 ms 折算）。
- ⇒ **不是"优化一下能跑"，是"差了三个数量级的硬件类别"。**

**阻断 3 · 平台形态**：它整机形态 = `LiDAR + Jetson Orin NX + 飞控`，即**默认你有伴生计算机**。我们已经审计过并**否掉了本板的协处理器**（`work/review-05-协处理器审计.md`：F103 外设引脚全悬空、PX4 零引用）。**它依赖的恰恰是我们主动放弃的那一环。**

#### (b) 只能借鉴思想？ —— **有 1.5 条，但都不解决我们当前任何问题**

诚实地说，能落到 MCU 上的只有下面这些；我把它们列全，**但不建议为此排期**：

| # | 可借的思想 | 怎么简化到 MCU | 对我们的实际价值 |
|---|---|---|---|
| 1 | **非对称因果门 `softplus(α·v_relᵀn)`**（式 8） | 纯算术：3 次点积 + 1 次 `expf`（M7 @480 MHz 约几百 cycle）+ 1 次 `log1p`。**完全可以塞进 1 kHz 循环**，无需训练（若按它训好的 `σ∥/σ⊥/α` 用就是查表级开销） | ⚠️ **没有输入**：`v_rel` 需要一个"相对位姿+相对速度"来源，我们没有对障碍物的量测。**留档，等有感知了再用** |
| 2 | **"离线蒸馏 / 把 O(|障碍|) 的在线优化换成 O(1) 的前向"** 范式 | 我们已经在做同类事（控制器增益、EKF 参数都是离线定好的）。**真正的启发是一条工程纪律**：凡是想往 1 kHz 环里塞优化迭代的，先问"能不能离线算好、在线退化成查表/闭式" | ✅ 作为**设计原则**成立，但它是**我们已经有的习惯**，不是新东西 |
| 2.5 | **头隔离 / 静态几何不被动态模块篡改**（§V-C2） | 模块解耦纪律：几何生成器与打分器分离 | ✅ 很弱的类比。唯一能对上的是我们踩过的坑——`SetAccelScaleAndRange()` 让**运行时回读**污染了"静态"标度（见 `work/review-04-加计单通道异常.md`）。但那是**代码 bug**，不是需要借别人的思想 |

**⇒ 我不能把结论写成"只借思想"**：因为这两条里，一条（非对称门）**缺输入、用不上**，另一条（离线蒸馏）**我们本来就在这么做**。把它们说成"值得借鉴"是**为了报告好看而拔高**，不诚实。

#### (c) 借鉴不了？ —— **这一条最贴近事实**

理由（按我们自身的约束排序）：
1. **算力**：无 GPU / 无 NPU / 无伴生计算机 ⇒ 22 M 参数、2.7 GMAC 的网络**物理上跑不动**（差 ~250× 延迟、差数十倍内存）；
2. **数据**：无 LiDAR ⇒ **没有它的输入模态**；无 GPU 训练，且板上无 USB/SD，训练数据都运不出来；
3. **传感器**：无 3D LiDAR、无深度相机、无毫米波雷达 ⇒ 连替代路径（换视觉）都缺硬件；
4. **任务不匹配**：RM2027 现在**根本没有"动态避障"这个需求**——我们卡在 **IMU 标定/加计增益异常/电调过零检测**（见 `work/review-01~05`）。**借一套避障规划器，不解决任何一条当前阻塞项。**
5. **许可**：MIT，**这一条不构成阻断**（唯一没问题的项）。

### 3.3 如果硬要做，最小可行验证方案（不推荐，仅按要求给出）

**前提**：必须先把 `3D LiDAR + 伴生计算机` 配齐（即判据 1 的"重装备"），否则实验无法启动。所以"MVP"的真实成本就是**买装备**（`Mid-360` + `Jetson Orin NX` 级别），我们一周内做不到，也不该做。

假设装备到位，理论上最短路径（复用它的开源件）：
1. 按 `README:166-171` 跑 `scripts/build.sh`（x86 仿真，需要 CUDA）；
2. 跑 `README:224-231` 生成数据集 + `train.py` 训练，或直接下 `README:174-186` 的预训练 `omnirisk_epoch60.pth`；
3. 在仿真里用 `README:192-216` 的 T1~T6 起 `sensor_simulator_cuda` + M-detector + `omnirisk_node.py`，在 RViz 里设目标点；
4. **成功判据（沿用论文 §VI-A）**：20 Hz 重规划、单周期规划 P95 < 50 ms、无碰撞抵达目标；真机再加"相对相遇速度 15 m/s 下连续规避"。
5. **⚠️ 我们现在的板子接进去只会变成"被 PX4 控的那台机器"**（`README:251-291` 走 MAVROS → PX4），**跟"借鉴到飞控上"不是一回事**。

**⇒ 这个 MVP 的本质是"把别人的无人机方案复刻一遍"，不是"借鉴到我们项目"。**

### 3.4 成本

| 项 | 内容 | 层次 |
|---|---|---|
| 硬件 | 3D LiDAR（Mid-360 级）+ 伴生计算机（Orin NX 级）+ 支架/供电 ⇒ **属于"很贵很重"的装备**（用户判断，我认同；**具体价格与重量本轮无法核实**，见 §5） | 【推理】 |
| 工作量 | 复刻：数周（仿真环境 + 真机部署 + 数据链路）；**要从零适配到 H743 上跑：不可行** | 【推理】 |
| 风险 | ① 我们的板子无 USB/SD，真机调试数据拿不出来；② 加装 LiDAR+Jetson 会改变整机重量/重心/振动，反过来**影响正在做的 IMU 标定**；③ 团队是竞赛队，投入产出比极差 | 【推理】 |

---

## 4. 总结（给决策用）

| 维度 | 判断 |
|---|---|
| 论文质量 | **好**。真机 15 m/s 连续规避、成功率 90.7%(室内)/86.7%(室外)、n=150、0 微调；消融做得细（输入张量消融、风险场消融、算力可扩展性）。**这不是一篇水论文。** |
| 代码质量 | **可复现性不错**：MIT、有预训练权重、有 docker、有 TensorRT 转换脚本、连 torch2trt 的 bug 都绕过了（`_CircularConv2d` 注释说明）。 |
| 与我们项目的匹配度 | **极低**。它假设 `LiDAR + 伴生计算机 + GPU`，我们三样都没有，且用户已明确放弃伴生计算机。 |
| **最终结论** | **★ 不值得投入。** 直接借鉴不可能（算力差 3 个数量级 + 感知模态缺失）；"思想"只有 1.5 条，一条缺输入、一条我们本来就在做，且**都不解决当前任何阻塞项**。 |
| 建议动作 | **只在 `work/` 留这份调研，不排期、不买硬件、不写代码。** 唯一值得抄进笔记的是式(8)那个非对称因果门——**等我们哪天有了相对位姿/速度量测再回头看**。 |

**⚠️ 反向提醒（避免误读）**：不要因为"贵和重"就认为这方法没价值——**在它自己的赛道上它是对的**：四旋翼躲高速飞来的球，用 LiDAR 换"不依赖视觉纹理 + 米制尺度 + 全向覆盖"是合理工程选择。
**它错配的是我们，不是我们错配了它。**

---

## 5. ⚠️ 本轮明确没查到 / 不能核实的（不编）

| 项 | 状态 | 原因 |
|---|---|---|
| 精确 star/fork 数的核验归属 | 只有 shields.io 回传值（stars **20** / forks **2**），**未从 GitHub 页面直接看到** | GitHub 直连失败；`ghproxy` 转发 GitHub **HTML/API/atom 全部 403**（`api.github.com`、`github.com/.../commits/main.atom`、`github.com/.../releases.atom` 实测均 403） |
| 最近提交的**确切日期**与 commit 数 | 只知 **"September"**、默认分支 **1 个 commit**、release **v1.0** | 同上，拿不到 commit 列表 |
| 网络**参数量 / FLOPs** | 论文与 README **均未给出**；§2.3 的数字是我按标准 ResNet-18 估算的 | 【推理】，请勿当引用数字 |
| Jetson Orin NX 的**具体型号/TOPS/功耗**、Livox Mid-360 的**价格与重量** | 论文只写"Jetson Orin NX"，未给型号；价格重量本轮未查 | 网络受限。**"贵和重"是定性判断（用户 + 我的推理），不是实测数字** |
| 演示视频内容（`README:11` YouTube 链接） | 未打开 | 非必要，且 YouTube 大概率不通 |
| 论文是否做过"用视觉/雷达替代 LiDAR"的迁移实验 | **没有**。相关工作里提了 vision/RGB-D/event camera 的**别人**的方法（§II），本文自己只在 LiDAR 平台上验证 | 【实测】（已通读 §II、§IV、§VI） |
| `requirements.txt` 里是否含 torch | 未列 torch（应该是另装/走 conda 或 docker），仓库根无 `environment.yml`（404） | 【实测】 |
| 图上/表格里的部分数值 | Table III 的 FAPP 在 |O|=4/6 的精确值被 HTML 截断，我只引了确定读到的数 | 诚实起见不补全 |

## 6. 复现命令（任何人可复核本文的每条【实测】）

```bash
# ① 论文存在性 + 元数据（HTTP 200）
curl -sI https://arxiv.org/abs/2609.18191 | head -1
# ② 全文（HTML v2）
curl -s -A "Mozilla/5.0" https://arxiv.org/html/2609.18191v2 -o omni.html

# ③ 仓库名纠错：Omini=404 / Omni=200
curl -s -o /dev/null -w "%{http_code}\n" \
  https://ghproxy.net/https://raw.githubusercontent.com/VANdexj/OminiRisk/main/README.md   # → 404
curl -s -o /dev/null -w "%{http_code}\n" \
  https://ghproxy.net/https://raw.githubusercontent.com/VANdexj/OmniRisk/main/README.md    # → 200

# ④ 关键源码（本文 §2.3 §2.4 引用到的文件）
B=https://ghproxy.net/https://raw.githubusercontent.com/VANdexj/OmniRisk/main
curl -s $B/OmniRisk/policy/network.py             # 双分支网络定义
curl -s $B/OmniRisk/policy/models/backbone.py     # 两个 ResNet18
curl -s $B/OmniRisk/policy/models/head.py         # 1×1 conv 评分头
curl -s $B/OmniRisk/config/traj_opt.yaml          # 96×384、36 个锚点、仰角 -7~52°
curl -s $B/OmniRisk/trt_transfer.py               # TensorRT fp16、H,W=96,384
curl -s $B/OmniRisk/train.py                      # 200 epoch / bs16 / lr1.5e-4
curl -s $B/LICENSE                                # MIT

# ⑤ 仓库统计（走 shields.io → 服务端查 GitHub API）
curl -s https://img.shields.io/github/stars/VANdexj/OmniRisk.json        # 20
curl -s https://img.shields.io/github/forks/VANdexj/OmniRisk.json        # 2
curl -s https://img.shields.io/github/commit-activity/t/VANdexj/OmniRisk.json  # 1
curl -s https://img.shields.io/github/last-commit/VANdexj/OmniRisk.json  # september
curl -s https://img.shields.io/github/v/release/VANdexj/OmniRisk.json    # v1.0
```

**声明**：本轮**未修改任何 PX4 源码、未连接硬件、未新建目录**；产出仅本文件 `work/review-06-OminiRisk调研.md`。
