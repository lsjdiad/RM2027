@echo off
wsl.exe -d Ubuntu-24.04 -- bash -c "cd /home/drone/PX4-Autopilot && HEADLESS=1 make px4_sitl gz_x500"
