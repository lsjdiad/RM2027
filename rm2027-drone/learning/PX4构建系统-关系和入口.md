# PX4 构建系统 · 关系和入口（像电控一样理解）

> 定位：把 `make px4_sitl gz_x500` 这条命令，翻译成电控能听懂的话。
> 核心观点：**Makefile 不是编译逻辑，它只是调度；CMake 才是构建图纸；Ninja 才是施工队。**
> 适合：已经看懂 shell 基础、正在读 PX4 启动脚本，但被 Makefile 吓到的人。

---

## 一、先用一张“机器人接线图”理解

```text
你输入的命令
  │
  ▼
Makefile
  │  作用：调度 / 转发
  ▼
CMake
  │  作用：读图纸，生成 build.ninja
  ▼
Ninja
  │  作用：真正编译 / 链接
  ▼
px4 二进制
  │  作用：飞控主程序
  ▼
启动脚本 rcS
  │  作用：上电初始化，选机型
  ▼
4001_gz_x500
  │  作用：设置这架飞机的参数
  ▼
gz_bridge + Gazebo
  │  作用：假传感器 / 假电机 / 物理世界
  ▼
QGC 地面站
```

---

## 二、每个东西对应电控里的什么

| PX4 里的东西 | 电控里的类比 | 作用 |
|---|---|---|
| `Makefile` | 总调度表 / 任务分配表 | 把命令转给 CMake |
| `cmake-build` | 调度函数 | 准备目录、配置、调用构建 |
| `CMakeLists.txt` | 工程图纸 / 模块依赖图 | 描述要编译什么、依赖什么 |
| `build.ninja` | 施工计划 | CMake 生成的构建文件 |
| `Ninja` | 施工队 | 真正调用 gcc / 链接器 |
| `px4` 二进制 | 主控程序 | 飞控真正运行的程序 |
| `rcS` | 上电启动流程 | 初始化、选机型、启动模块 |
| `4001_gz_x500` | 机型参数表 | 电机数量、位置、转向、参数 |
| `model.sdf` | 机械 / 电机模型 | Gazebo 里的虚拟飞机 |
| `gz_bridge` | CAN / 传感器驱动 | PX4 和 Gazebo 之间的数据桥 |
| QGC | 遥控器 / 地面站 | 看状态、发指令 |

---

## 三、`make px4_sitl gz_x500` 到底发生什么

```text
make px4_sitl gz_x500
│
├── Makefile
│   ├── FIRST_ARG = px4_sitl
│   ├── ARGS = gz_x500
│   │
│   └── 调用 cmake-build px4_sitl_default
│       │
│       ├── 准备 build/px4_sitl_default
│       ├── 运行 cmake 配置
│       │   └── 生成 build.ninja
│       │
│       └── cmake --build ... -- gz_x500
│
├── CMake 找到 gz_x500 目标
│   └── src/modules/simulation/gz_bridge/CMakeLists.txt
│       └── add_custom_target(gz_x500 ...)
│
├── 运行 px4 二进制
│   └── 环境变量 PX4_SIM_MODEL=gz_x500
│
├── rcS 根据 PX4_SIM_MODEL 匹配机型
│   └── 4001_gz_x500
│
├── 4001_gz_x500 设置参数
│   ├── CA_ROTOR_COUNT 4
│   ├── CA_ROTOR0_PX / PY / KM
│   └── SIM_GZ_EC_*
│
├── px4-rc.gzsim 启动 Gazebo
│   ├── gz sim
│   └── gz_bridge
│
└── model.sdf 描述虚拟飞机
    ├── 机身
    ├── 4 个电机
    ├── 桨
    └── 传感器
```

---

## 四、它是怎么让飞机“飞”的

```text
1. Gazebo 里加载 x500 模型
2. PX4 通过 gz_bridge 读假传感器数据
3. PX4 跑姿态 / 位置控制
4. PX4 输出电机转速
5. gz_bridge 把转速给 Gazebo
6. Gazebo 算出飞机下一帧的位置 / 姿态
7. 回到第 2 步，持续循环
```

所以本质是：

```text
PX4 负责“控制”
Gazebo 负责“物理世界”
gz_bridge 负责“通信”
QGC 负责“人机界面”
```

---

## 五、你只需要看的 5 个位置

```text
1. Makefile
   → 只看 FIRST_ARG / ARGS / cmake-build / cmake --build

2. src/modules/simulation/gz_bridge/CMakeLists.txt
   → 只看 gz_x500 目标怎么定义

3. ROMFS/px4fmu_common/init.d-posix/rcS
   → 只看 PX4_SIM_MODEL 怎么选机型

4. ROMFS/px4fmu_common/init.d-posix/airframes/4001_gz_x500
   → 只看 CA_ROTOR_* 和 SIM_GZ_EC_*

5. Tools/simulation/gz/models/x500/model.sdf
   → 只看电机 / 桨 / 传感器
```

---

## 六、可以暂时忽略的东西

```text
CMakeCache 检查
NuttX 子模块清理
Ninja / Make 生成器切换
bootloader / CI / 测试
静态分析 / 文档生成
```

这些是工程细节，不是你现在的主线。

---

## 七、一句话记忆

```text
Makefile = 调度
CMake    = 图纸
Ninja    = 施工
px4      = 主控程序
rcS      = 上电流程
4001     = 机型参数
model.sdf = 虚拟飞机
gz_bridge = 数据桥
QGC      = 地面站
```

---

## 八、你现在的心智模型

```text
看到 make 命令
→ 不要想“它在编译”
→ 先想“它在把任务交给 CMake”

看到 CMake
→ 不要想“它在编译”
→ 先想“它在生成 build.ninja”

看到 Ninja
→ 这才是真正编译
```

---

> 结论：你不需要读完整个 Makefile。
> 你只需要知道：谁调用谁，参数怎么传，最后谁让飞机飞起来。
