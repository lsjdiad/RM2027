#!/usr/bin/env bash
# 启动 PX4 SITL + Gazebo（x500 四旋翼）
cd "$(dirname "$0")/PX4-Autopilot" || exit 1
exec make px4_sitl gz_x500
