# 待烧录 · 分支 review：`imu/bmi270-datasheet-followups`

> 2026-09-30 夜 · 作者：并行子代理（本文件由该子代理撰写，提交由 Lead 复核）
> 分支基点：`bringup/imu-polled-and-params` @ **`b1f1abb`**（= Lead 当时的最新 HEAD，含我之前全部改动 + Lead 的四笔修正）
> 分支内容：**`95d6ac7`（Lead 已复核入库）+ `f505644`（本轮新增）**
> 完整 patch 存档：`work/spi-runtime/patch-imu-bmi270-datasheet-followups.diff`（358 行）

## 0. 为什么要开这个分支

用户提出一个很有说服力的假设：**「静止 1g 只读到 ~1185 counts（手册 2048）」可能不是硅片增益问题，
而是【初始化时配置没真正生效】** —— 依据是他让我看厂商手册，而手册给了三条 PX4 没遵守的时序要求，
且我自己的扫描里已经出现过"配置生效与否取决于写入顺序"的迹象（`ACC_CONF=0x0C` 时量程寄存器像失效；
`bwptest` 里读数只有 1177/2302 两个离散档而回读恒等于写入值 = 影子寄存器）。

本分支就是把"按手册把配置/识别/自查做对"这件事落成代码，并**给出判断 1.73x 性质的第一手证据**。

## 1. 这个分支改了什么（5 件事）

| # | 改动 | 依据（厂商手册，华轩阳 HXY「ICM-42688P」） |
|---|---|---|
| 1 | **兼容件识别改用 `WHO_AM_I(0x01)==0x6A`**，保留 `CHIP_ID(0x00)==0x00` 作兜底（即使 0x01 不是 0x6A 也不会退化成"驱动起不来"） | §4.1/§5.1：ID 在 0x01、缺省 0x6A；0x00 不在表里 |
| 2 | **配置时序重排**：`PWR_CTRL=0x00`(全关) → 1ms → 写 `GYR_CONF` → `PWR_CTRL=0x0E` → 10ms → 写 `ACC_CONF/ACC_RANGE` → 1ms → 回读 | §5.39（`GYR_NOISE_PERF` 必须**关着写**，而 0xEC 正含该位）＋ §5.45（0x7D 先写 0x0E 延 10ms；配完延 1ms 再读） |
| 3 | **不再碰 `PWR_CONF(0x7C)`**：`Configure()`、周期性回读、以及 `WAIT_FOR_RESET`（`f505644` 补掉）全部跳过 | §4.1：本片表里**没有 0x7C**，且"保留地址不要改、可能永久损坏" |
| 4 | **新增 `DATA_STAT(0x0B)` 配置自查**：每次配置完读一次，报 `ACC_CONF_ERR`/`GYR_CONF_ERR`（置位就计入 `_bad_register_perf`）；`bmi270 status` 里也能看到快照 | §5.8（位定义）＋§5.37（非法组合会回落缺省值并置位） |
| 5 | 注释更正：寄存器表里"本板器件没有 FIFO"的旧表述改成"FIFO 在 0x1C~0x21，是地址不对不是没有 FIFO" | §5.16~§5.21 |

**未包含（有意不做）**：
- 不动 `set_range()`/标定系数（1.73x 未定论前不动）；
- 不实现本片 FIFO 路径（0x1C~0x21）—— 属功能增强，不是当前阻塞项；
- 不在驱动里做 FIFO 测 ODR（诊断放 `cleaninit.tcl`，飞行代码不背负诊断事务）；
- 不动 `STATE::RESET` 的"跳过软复位"（本片正确软复位是 `SOFT_RST(0x4A)=0xA5`，但**未验证**，不赌）。

## 2. 上板后按这个顺序看（决定性顺序）

```bash
# 1) 启动日志（ST-Link 读 console 或 QGC MAVLink Console）
#    期望看到（原文）：
#      BMI270-compatible part detected (WHO_AM_I(0x01)=0x6a, CHIP_ID(0x00)=0x00): microcode upload will be SKIPPED
#      compatible part: DATA_STAT(0x0B)=0x?? ACC_CONF_ERR=? GYR_CONF_ERR=?
#      bmi270 #0 on SPI bus 1
#      Skipping BMI270 microcode upload (compatible part)     ← 只应出现 1 次
```
**第 2 行是本轮最重要的信息**：
- `ACC_CONF_ERR=0 && GYR_CONF_ERR=0` ⇒ 配置被器件接受了 ⇒ 读数若仍是 ~1185 counts/1g，那就**排除了"配置没生效"**，
  1.73x 回到"增益 vs 零偏"问题 ⇒ 做**翻板实验**（翻过来看 |a|：不变=增益；变到 ~1.4g=零偏）。
- 若 `ACC_CONF_ERR=1` 或 `GYR_CONF_ERR=1` ⇒ **配置没生效**（芯片已回落缺省 0xA8/0xA9 = 100Hz/200Hz），
  那 1185 就不能当"器件增益"证据，应先修配置（下一步：照 `cleaninit.tcl` 的顺序矩阵逐格试，
  并用 FIFO 组数实测真实 ODR —— 若真停在 100Hz，Lead 加的"重复样本抑制"就是必需的保险）。

```bash
# 2) 数据是否真的在发布（QGC MAVLink Console；/dev/ttyUSB0 被 QGC 占着，别抢串口）
listener sensor_accel     # 静止：|a|≈9.8 m/s²、z≈-9.8
listener sensor_gyro      # 静止：三轴接近 0

# 3) 诊断计数器（判断 ODR 到底多少）
bmi270 status             # 看 "duplicate sample" 计数是否长期快速上涨
                          #   ≈0        ⇒ ODR 真的 ≥1kHz
                          #   持续上涨  ⇒ ODR 远低于 1kHz（配置没生效的现场证据）
```

```bash
# 4) 若要走 ST-Link 手工判定（板子断电/或 QGC 不做时）
openocd -f work/spi-runtime/cleaninit.tcl
#   9 个"时序×量程"组合各 20 样本 + DATA_STAT 错误位 + 用本片 FIFO 实测 ODR
#   判据：某组合 |a|≈2048 ⇒ 之前的 1185 是配置假象（1.7283 系数必须撤）
#         全组合仍 ~1185 ⇒ 时序不是原因，做翻板/自测
```

## 3. 回滚/切换成本

- 全部改动都在兼容件分支（`_skip_microcode == true`）内，**正品 BMI270 路径零改动**；
  换回正品芯片时这份代码不需要回滚。
- 若只想回到上一版行为：`git revert f505644 95d6ac7` 即可（两笔都是自包含的）。
- 红线未动：**兼容件仍然绝不上传微码**（上传会把器件锁死，只能断电恢复）。
