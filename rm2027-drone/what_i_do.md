# what_i_do

> 学习 / bring-up / 校准记录

---

## 00 环境与工具

- `/home/xien/桌面/RM2027/PX4-Autopilot/Tools/setup/`

  ```bash
  bash ubuntu.sh
  ```

- `'make px4_sitl gz_x500'` return error

  ```text
  find lose python pip
  dsh install python pip on px4's python3.12
  root cause: bash ubuntu.sh install everything on system python3
  resolve wat: dsh change env variable (a cmake cache) to redirect it to system python3
  ```

- `~/Applications/QGroundControl.AppImage`
  run qgc from home directory

---

## 01 QGC 基础

### 参数修改

- QGC -> Q -> Paramaters -> search `-?mis_takeoff_alt` change from 2.5 to 8

### 学习视频

- learn qgc5 from https://www.bilibili.com/video/BV1hoXzBwED3/
  a little diff exist between latest qgc and shown in vedio, have a basic undestanding about it
- learn qgc mission creat and basic use from BV1GV411V76N

### 虚拟摇杆

- Q -> Settings -> Fly View -> Virtual Joystick -> on
  and joystick mapping rules are as follows

  ```text
  Left stick up/down      → altitude
  Left stick left/right   → yaw
  Right stick up/down     → pitch
  Right stick left/right  → roll
  ```

### 待复现的文章

- reproduce the steps in following article
  - https://mbot1.blog.csdn.net/article/details/140664673 (this contains a lot of qgc gui change, if someday we want to change to show more drones at the same time, then learn it)
  - https://mbot1.blog.csdn.net/article/details/122532570 (show the architecture of PX4)

---

## 02 仿真与模型

- read `/home/xien/桌面/RM2027/PX4-Autopilot/Tools/simulation/gz/README.md`
  (introduce some dependency repo and how to use with a python file? which is the old ones)

- read `Tools/simulation/gz/models/x500/model.sdf`
  - sdf -> simulation description format, use xml (eXtensible Markup Language) language
    xml can be transmit into DOMtree (Document Object Model)
    - xml language learning:
      - BV19t4y1E7nR (quick start)
      - BV1Na4y1J75w (basic syntax)
  - use

    ```xml
    <include merge='true'>
      <uri>model://x500_base</uri>
    </include>
    ```

    to inherit a drone model and set unique motor paramater in this file

- read 'PX4-Autopilot/Tools/simulation/gz/models/x500_base/model.sdf'
  -describe the body(shape ,look and collision boxes),sensors(air pressure sensor , magnetoment ,IMU and GPS),motors ,joints

---

## 03 PX4 启动脚本

- read `ROMFS/px4fmu_common/init.d-posix/airframes/4001_gz_x500`
  - this file is a shell script ,https://www.bilibili.com/video/BV17m411U7cC/ this is a beginner vedio of shell ,i still couldn't understand some of it's code
    - `. ${R}etc/init.d/rc.mc_defaults`   include root of project(or ROMS)'s file and excute it right now   couldn't find this file

---

## 04 文档阅读笔记

- read ~/RM2027/PX4-Autopilot/docs/en/config/airframe.md , explain how to use set frame on QGC ,recommond me to read [Actuator Configuration & Testing](../config/actuators.md) and [ESC Calibration](../advanced_config/esc_calibration.md) (As for Dshot ,We don't have to read this artical)

- read actuators.md
  some important information

  > ::: info The X, Y, Z positions are in FRD coordinate frame, relative to the centre of gravity. Note, this may not be the same as the position of the flight controller! :::
  >
  > Note that you will also need to ensure that the ESC associated with bidirectional motors is configured appropriately. For DShot ESC you will need to enable 3D mode using DShot commands.(what is 3D mode still unkonwn)

  ```text
  WM MAIN   I/O Board（协处理器）   PWM MAIN   经过中间芯片，延迟稍高
  PWM AUX   FMU（主处理器）         PWM AUX    主控直连，延迟更低，响应更快
  ```

  ```text
  物理输出（Output）：指的是飞控上具体的引脚，例如 AUX1、MAIN2。
  功能（Function）：指的是这个引脚“扮演什么角色”（比如：它是不是1号电机？是不是云台？）。
  参数（Parameter）：指的是你给这个引脚设定的具体数值（例如：PWM_AUX_MIN1 是 1000，
  ```

  Output Assignment and Configuration  :this section mainly describe how to set the right parameter

- read docs/en/concept/system_startup.md
  px4fmu_common folder has two kind of init that we should pay attention to

---

## 05 构建链路（Makefile → CMake → Ninja → PX4）

- read PX4-Autopilot/Makefile,Cmakelist.txt

  ```text
      make px4_sitl gz_x500
      │
      ├── [1] Shell / Make 解析层
      │   ├── MAKECMDGOALS = px4_sitl gz_x500
      │   ├── FIRST_ARG = px4_sitl
      │   ├── ARGS = gz_x500
      │   ├── SRC_DIR = /path/PX4-Autopilot
      │   ├── ALL_CONFIG_TARGETS：
      │   │   └── boards/**/*.px4board
      │   │       ├── boards/px4/sitl/default.px4board   → px4_sitl_default
      │   │       ├── boards/px4/fmu-v5/default.px4board → px4_fmu-v5_default
      │   │       └── ...
      │   ├── CONFIG_TARGETS_DEFAULT：
      │   │   └── px4_sitl / px4_fmu-v5 / ...
      │   └── PX4_CMAKE_GENERATOR = Ninja
      │
      ├── [2] Make 目标匹配层
      │   ├── px4_sitl
      │   │   ├── 命中 $(CONFIG_TARGETS_DEFAULT):
      │   │   ├── $@ = px4_sitl
      │   │   ├── $@_default = px4_sitl_default
      │   │   └── $(call cmake-build,px4_sitl_default)
      │   └── gz_x500
      │       ├── 命中 %:
      │       ├── $(filter $(FIRST_ARG),$@) = 空
      │       └── @# → 不执行，仍留在 ARGS
      │
      ├── [3] cmake-build 函数层
      │   ├── $(1) = px4_sitl_default
      │   ├── CMAKE_ARGS += -DCONFIG=px4_sitl_default
      │   ├── BUILD_DIR = build/px4_sitl_default
      │   ├── cmake-cache-check
      │   ├── 必要时清理 NuttX / build
      │   └── cmake "$(SRC_DIR)" -G Ninja -DCONFIG=px4_sitl_default
      │
      ├── [4] CMake Configure 层
      │   ├── 顶层 CMakeLists.txt
      │   │   ├── CMAKE_MODULE_PATH += cmake/
      │   │   ├── include(px4_parse_function_args)
      │   │   ├── include(px4_git)
      │   │   ├── include(px4_add_module)
      │   │   ├── include(px4_config)
      │   │   │   └── 用 CONFIG 找到 boards/px4/sitl/default.px4board
      │   │   ├── include(kconfig)
      │   │   │   ├── 读 .px4board
      │   │   │   ├── 生成 boardconfig
      │   │   │   ├── 生成 px4_boardconfig.h
      │   │   │   └── 生成 config_module_list
      │   │   └── include(px4_add_library)
      │   │
      │   ├── add_subdirectory(src/lib)
      │   ├── add_subdirectory(platforms/posix/src/px4)
      │   ├── add_subdirectory(platforms)
      │   ├── if board CMakeLists：add_subdirectory(boards/...)
      │   ├── foreach(module in config_module_list)
      │   │   └── add_subdirectory(src/${module})
      │   │       └── src/modules/simulation/gz_bridge/CMakeLists.txt
      │   │           ├── px4_add_module(...)
      │   │           └── add_custom_target(gz_x500 ...)
      │   ├── add_subdirectory(src/lib/events)
      │   ├── add_subdirectory(src/lib/metadata)
      │   ├── add_subdirectory(src/lib/parameters)
      │   └── add_subdirectory(platforms/posix)
      │
      ├── [5] CMake 生成物
      │   ├── build/px4_sitl_default/CMakeCache.txt
      │   ├── build/px4_sitl_default/build.ninja
      │   ├── build/px4_sitl_default/boardconfig
      │   ├── build/px4_sitl_default/px4_boardconfig.h
      │   └── build/px4_sitl_default/etc/
      │
      ├── [6] CMake Build / Ninja 层
      │   ├── cmake --build build/px4_sitl_default -- gz_x500
      │   └── Ninja
      │       ├── 读 build.ninja
      │       ├── 依赖 bin/px4 + px4_gz_plugins
      │       ├── 编译/链接 px4
      │       └── 执行 gz_x500 规则
      │           ├── cd .../gz_bridge
      │           ├── PX4_SIM_MODEL=gz_x500
      │           ├── GZ_IP=127.0.0.1
      │           └── .../bin/px4
      │
      └── [7] PX4 运行层
          ├── px4 启动
          ├── 执行 etc/init.d-posix/rcS
          ├── rcS 读 PX4_SIM_MODEL=gz_x500
          ├── 匹配 4001_gz_x500
          ├── SYS_AUTOSTART=4001
          ├── 执行 4001_gz_x500
          ├── px4-rc.gzsim：gz sim + gz_bridge
          ├── model.sdf：虚拟飞机
          └── QGC：MAVLink 14550
  ```

---

## 06 待读 / 待答（control_allocation 等）

- read docs/en/concept/control_allocation
  - a picture of acuator control pipeline is crutial
  - does testing acuator use actuactor_test uorb message?and how does ouutput drivers handle those different uorb message?
  - how do output drivers use a shared liberary??
  - as for mapping of acuators ,let me read actuactor later
  - use commit for further self use (it seems i shouldn't take more attention on it ,what i use is just a normal drone,perhaps i just select on QGC is enough)

- read:/docs/en/airframes/airframe_reference.md
  - give some reference model of quadRotorX(4001_ was it's SYS_AUTOSTART's value which it's default for the quadrotorx )

- read:docs/en/config/gyroscope.md
  - it lets me just connect to the vehicle and run the calibration 
  - as for configing different i/o pin and different kind of gyro,it will be shown later 
  - how to connect QGC and FMU? mavlink? us a uart as mavlink qgc connect with fmu throughit




QGC Vehicle Setup?
---

## 07 todolist

```text
3. `ROMFS/px4fmu_common/init.d-posix/airframes/4001_gz_x500`

docs/en/config/gyroscope.md
docs/en/config/accelerometer.md
docs/en/config/compass.md
docs/en/config/radio.md
docs/en/config/actuators.md
docs/en/advanced_config/esc_calibration.md
docs/en/advanced_config/parameter_reference.md

4. `src/examples/hello`
5. `src/modules/` 里自己关心的模块
```

todolist:

- `PX4-Autopilot/Tools/simulation/gz/models/x500/model.sdf`, `ROMFS/px4fmu_common/init.d/airframes/4019_x500_v2`
  px4 use this to describe and establish a virtual drone, i'll shall read about it (how the motor and whether we can define by ourselves)


ai写了两天的代码,产出了很多commit消息,初步达到稳定态
人工复合一遍
https://github.com/PX4/PX4-Autopilot/fork 执行fork,并只fork主分支
git remote rename origin upstream      # ① PX4 官方 → upstream
git remote add origin <你 fork 的 URL>  # ② 你的 fork → origin
改名
git remote -v && git branch -vv         # ③ 复核角色与跟踪关系
检查远端信息和分支详细信息
git push -u origin h104-protocol        # ④ 之后 push 默认就是你的 fork
在origin 创建一个分支,把本地分支pull上去,并且建立起跟踪关系
git push origin teaching/clean teaching/minimal-path

git switch -c learn/rm2027  开始在学习分支上准备重构
