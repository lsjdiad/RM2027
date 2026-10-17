# 资源包 · PX4 / QGC / SITL 讲解视频清单

> 2026-09 整理。按你的水平（SITL 已跑通、在搞二次开发/硬件）分级推荐。BV 号可 B站 搜索。

## 一、SITL / 仿真入门（环境已通，回顾/对照用）

| BV | 标题 | 用途 |
|----|------|------|
| BV1Fpxxz9EYR | Ubuntu24.04 运行 PX4 SITL（Gazebo 仿真器） | 跟你环境同款，对照排错 |
| BV1fNtA6CE4i | PX4 与 Gazebo 联合仿真 · SITL 编译与 Iris 启动 | 理解 SITL 怎么起的 |
| BV1px4y1N7tv | 多旋翼入门 · Gazebo 仿真 | 概念补课 |
| BV16N4y1d7Ki | PX4 仿真环境 + Simulink/Gazebo 联合 | 进阶（要仿真验证控制）|

## 二、QGC 地面站（你要用的）

| BV | 标题 | 用途 |
|----|------|------|
| BV1GV411V76N | QGC 入门教学（中文配音） | 界面全貌（之前推荐过）|
| BV1icSbYzE82 | QGC 地面站教程合辑 | 系统跟 |
| BV1KyxFePEmu | QGC 航线规划教程 | Plan 画航点 |

## 三、★ PX4 二次开发 / 架构（你现在最需要的）

| BV | 标题 | 对应你的需求 |
|----|------|-------------|
| BV1WU421Z7Kw | PX4 二次开发快速入门（一）概述 | 理解 PX4 怎么扩展 |
| **BV14M4m1Z7sR** | **PX4 二次开发（三）自定义串口驱动** | ★ 就是"写 HI04 UART 驱动"的模板！|
| **BV1Wb4y1A71V** | 速成 PX4 二次开发 03 · 自定义 uORB 消息并发布 | ★ 怎么发布自定义数据 |
| BV1jb421h7aN | PX4 二次开发快速入门 2.2 · 自定义 uORB 消息 | 同上传补充 |
| BV16dkSBjEg8 | PX4 源码的编译 | 编译/烧录流程 |
| BV1FxvkBuE17 | PX4 + Gazebo + ROS2(C++) 写飞行控制 | 你之前问 ROS2 的参考 |

## 四、Offboard / 外部控制（L05 自主飞行相关）

| BV | 标题 |
|----|------|
| BV1nV4y1R7Z9 | PX4 Offboard 键盘控制飞行仿真 |
| BV1R7411R7wf | 快速实现 PX4 Offboard + Gazebo（GAAS）|
| BV1phL1z9Ekw | ROS+PX4+Gazebo offboard 多无人机编队 |

## 五、推荐观看顺序（结合你现状）

```
1. 【三】BV14M4m1Z7sR 自定义串口驱动 ← 如果你要写 HI04 驱动，先看这个
2. 【三】BV1Wb4y1A71V 自定义 uORB ← 理解数据怎么进 PX4
3. 【三】BV1WU421Z7Kw 二次开发概述 ← 架构
4. 【一】对照 SITL（环境已通，需要时看）
5. 【二】QGC 系列（要画航点/调参时）
```

> 核心：**你要么走"SPI 裸 IMU"（不用看驱动开发，PX4 原生），要么走"写 HI04 UART 驱动"（BV14M4m1Z7sR 就是模板）**——先定走哪条，再决定看不看二次开发视频。

## 关联资料
- `learning/资料-HI04外置IMU接PX4调研.md`（为什么 UART IMU 特殊）
- `learning/资料-浙大课程成本与周期.md`（Fast-Lab 实机复刻课）
- PX4 官方：docs.px4.io（Dev Guide → Module/Driver 编写）
