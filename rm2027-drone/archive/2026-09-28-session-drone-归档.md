# drone 会话归档（2026-09-28）

- 来源 DSH 会话：`session-f10279b3-8e15-49bf-a941-ee689720e970`
- 会话标题：drone
- 工作区：`/mnt/h/AI/shared`
- 归档日期：2026-09-28
- 说明：该会话上下文曾超限，这份是自动生成的 checkpoint 摘要；原始完整会话仍保留在 DSH 里。

---

## Primary Request and Intent
- Focus on the drone project: `projects/competition/rm2027-drone` — "专注于drone这个project,你知道我在说什么吗?"
- Evolved into: learn PX4/QGC/SITL by doing, then bring up a teammate-built flight controller board.
- User's role clarified: "我是我们有人专门画硬件飞控板，有人专门负责机械，我负责是他们给我搞出来东西之后，我要去干活" → firmware bring-up, driver porting, sensor/motor debugging, tuning, log analysis, integration (UWB, 机库).
- Wants to build a self-defined drone eventually, test drivers/ESC in a room: "我想实际的去试一试，调试一下".
- Explicit learning-workflow request: "我在思考一个问题,可不可以引入一个学习的工作流,去让我由浅入深地快速学习" — wants notes styled like their existing RM electric-control knowledge base (`rm-electric-knowledge-base`, `02_code_twin`, `03_moc`), with 00/01/02/03 layered notes and trees.
- Latest intent (seq 406419): rejects prior PX4 build tree as mere repackaging — "我感觉你只是把原有的东西放到一起，然后给他们起了1个不同的名字，并不符合。我觉得你应该重构去达到的1个事情" … "像后边的CMake配置阶段和CMake构建阶段，他们中间的参数传递我就已经有点看不太懂了，为什么最终会匹配到rcS这个目录啊？"
- Standing reply rules (must obey): always answer in Chinese; end every reply with a `📝 英文小改` table (format "我写的 → 正确写法"); be concise, bulleted, no waffling.

## Key Technical Concepts
- PX4-Autopilot (main branch), SITL, Gazebo Harmonic (gz-harmonic 8.15.0, not Garden), QGroundControl v5.1.3
- Two-layer build: top-level `Makefile` = dispatcher; CMake = build-file generator; Ninja = build executor; gcc/clang = compiler
- Makefile `:=` immediate expansion; `$@`, `$(1)`, `$(filter)`, `$(patsubst)`, `$(wordlist)`, `$(if)`, `$(error)`, `$$` escaping
- `.px4board` Kconfig files → `boardconfig`, `px4_boardconfig.h`, `config_module_list`
- `PX4_SIM_MODEL` (run-time airframe selection) vs `CONFIG` (compile-time board selection)
- uORB messaging, EKF2, mc_pos_control, mc_att_control, control allocation (`CA_AIRFRAME`, `CA_ROTORn_PX/PY/KM`)
- `MIS_TAKEOFF_ALT` (default takeoff alt), `RTL_RETURN_ALT` (60m default), `RTL_DESCEND_ALT`
- DShot / BDShot / CAN (DroneCAN/UAVCAN, `UAVCAN_ENABLE=3`), FD6288Q 3-phase gate driver
- STM32H743VIT6 / STM32F103C8T6 / STM32G071GBU6N; only TIM1/TIM8 are advanced timers with CHxN + dead-time on F103; F103 has no CH4N
- ST-Link / OpenOCD / gdb-multiarch / Cortex-Debug; VSCode Profiles (default / c / python / embedded)
- RM2027 rules: 150–249g, 60–140mm envelope, 4 aircraft, 机库 300×300×200mm, 30s endurance, UWB positioning, 桨保 required

## Files and Code
- `/mnt/h/AI/shared/projects/competition/rm2027-drone/` — H:\AI\shared\projects\competition\rm2027-drone
- `.../learning/PX4构建-因果链.md` — **newest deliverable**, 238 lines; separates 配置链 (FIRST_ARG → px4_sitl_default → -DCONFIG → .px4board → config_module_list → gz_bridge) from 运行链 (ARGS → gz_x500 → PX4_SIM_MODEL → rcS → 4001_gz_x500)
- `.../learning/PX4-build-walkthrough.md` — mirrored to `E:\STM32project\rm-note\rm-electric-knowledge-base\03_moc\PX4-build-walkthrough.md`
- `.../learning/PX4构建系统-关系和入口.md`, `.../learning/PX4构建系统-00-08分层笔记.md`, `.../learning/软件知识地图-最短路径.md`
- `.../references/硬件手册/` — `FMU_飞控板_原理图_2026-09-24.pdf`, `ESC_电调板_原理图_2026-09-24.pdf`, `STM32H743VI_datasheet_extract.md`, `ICM-42688-P_datasheet_extract.md`, `FD6288Q_datasheet_extract.md`, `SIT3051TK_datasheet_extract.md`, `INA240_datasheet.pdf`, `TLV755P_datasheet.pdf`, `TLV767_datasheet.pdf`, `WS2812B_datasheet.pdf`, `硬件手册索引与关键参数.md`
- `.../references/超维空间科技-CSDN文章清单.md` (99 links), `超维空间科技-免费精选文章.md`, `自主拦截与定位-资料来源.md`, `TWZ-无人机相关文章链接.md` (167 articles)
- `/home/xien/桌面/what_i_do.md` — reformatted to Markdown (00 环境与工具 … 07 一句话), TODO updated for hardware phase
- `/home/xien/RM2027/fmu_test/` — H743VIT6 bare-metal test: `Makefile`, `src/main.c`, `src/startup_stm32h743xx.s`, `ld/STM32H743VITx_FLASH.ld`, `openocd.cfg`, `.vscode/{settings,launch,tasks}.json`; builds to 148 bytes text
- `/home/xien/RM2027/f103_test/` — same structure for STM32F103C8T6
- `/home/xien/桌面/RM2027/mas_embedded_threadx/` — teammate RM project; `.vscode/{settings,launch,tasks}.json`, `.vscode/flash_interactive.{sh,bat}` updated with Linux paths, `f103_c8` + `fmu_h743` cases, `damiao_h7` JLink device corrected to `STM32H723VG`; new `docs/Ubuntu环境检查与部署.md`
- `/home/xien/.config/Code/User/globalStorage/storage.json` — profiles: `-234a8062`=c, `-3571b125`=python, `-embeded`=embedded (new)
- `/home/xien/桌面/open-dsh.sh`, `/home/xien/桌面/AI/shared/restart-dsh.sh`, `~/.local/bin/dsh-redirect.py` (port 3082 `/go` redirector)

## Errors and Fixes
- `Cipher functions:OPENSSL_internal:BAD_DECRYPT` on VSCode extension install → Clash Verge proxy at 127.0.0.1:7897 intercepting gallery; fixed with `env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY code --profile "c" --install-extension <id>`
- `/etc/apt/sources.list.d/ros-fish.list` pointed to jammy on noble → deleted; `docker.list` jammy → rewritten to noble
- `make px4_sitl gz_x500` failed on missing python pip → CMake cache/env redirected to system python3.12
- fmu_test / f103_test `Makefile:24: *** 缺失分隔符。 停止。` → generated recipe lines used spaces; converted to tabs via Python script
- `damiao_h7` JLink device mismatch (`STM32H743BI` vs code's H723) → changed to `STM32H723VG` to match `startup_stm32h723xx.s`, `STM32H723.svd`, `STM32H723XG_FLASH.ld`
- f103_c8 build failure: default `REMOTE_UART = huart3` but board only has `huart1`/`huart2` → board/robot-level override needed (code issue, not env)
- `arm-none-eabi-gdb` missing → use `gdb-multiarch` (`cortex-debug.gdbPath.linux`)
- Vim swap file `ROMFS/.../.4001_gz_x500.swp` → removed, file was unmodified (git clean)
- `PTY shell exited during startup` → user fixed; shell confirmed working (`pwd` = /mnt/h/AI/shared)
- CSDN article scraping blocked by WAF/安全验证 → used `https://r.jina.ai/` proxy successfully
- DSH phone auth failures → root cause missing `--trusted-host ubuntu-24.tail0c65e9.ts.net`; `/go` short link via tailscale serve on 3082

## Pending Jobs
- User must download STM32CubeMX Linux zip manually (needs ST account login; free): `en.stm32cubemx-lin-v6-18-1.zip` → unzip to `~/toolchains/STM32CubeMX`; OpenJDK 17 already installed
- Create PX4 board support for the new FMU board (`board/fmu_h743` or final English name) — user confirmed firmware route is PX4
- Information-flow tracing (`listener sensor_gyro/sensor_accel/vehicle_attitude/actuator_motors`, `uorb top`)
- Parameter calibration sequence: 陀螺仪 → 加速度计 → 磁罗盘 → 水平 → RC → ESC/DShot → 执行器(电机顺序/转向) → EKF2 → Hover throttle → Rate/Position PID
- Decide UWB feasibility (needs pre-placed ground anchors) vs 光流/ToF/VIO fallback
- Rename `fmu_test`/`f103_test` when the flight controller's English name is fixed

## Current Work
- Responding to the user's rejection of the merged build tree as non-refactored; wrote `PX4构建-因果链.md` and explained in-reply:
  - rcS is NOT matched by CMake — CMake only compiles `bin/px4` and copies `ROMFS/px4fmu_common` to `build/.../etc`; PX4 binary always reads `build/px4_sitl_default/etc/init.d-posix/rcS` at startup.
  - rcS resolves airframe via `sed -n 's/^\([0-9][0-9]*\)_'${PX4_SIM_MODEL}'$/\1/p'` on `etc/init.d-posix/airframes`, yielding `4001_gz_x500`, then sets `SYS_AUTOSTART=4001`.
  - Two chains converge at target `gz_x500`: 配置链 uses FIRST_ARG, 运行链 uses ARGS.
- Two-layer build already validated: `make px4_sitl gz_x500` → `cmake --build build/px4_sitl_default -- gz_x500` → Ninja target defined in `src/modules/simulation/gz_bridge/CMakeLists.txt` via `add_custom_target(gz_x500 ...)` with `PX4_SIM_MODEL=gz_x500 GZ_IP=127.0.0.1 $<TARGET_FILE:px4>`.

## Next Step
- Await user confirmation on whether `PX4构建-因果链.md` now satisfies the refactor demand; if yes, proceed to PX4 board bring-up for the new H743 FMU (`board/fmu_h743`) and sensor information-flow tracing. If not, deepen the CMake configure→build parameter-passing explanation (specifically `CMAKE_ARGS` → `cmake/px4_config.cmake` → `PX4_CONFIG_FILE` → `cmake/kconfig.cmake` → `config_module_list` → `add_subdirectory`).

## Critical Context
- **Reply format is a hard user rule**: Chinese only; concise bullets; end with `📝 英文小改` table (我写的 → 正确写法).
- User prefers explanations rooted in an entry command they can follow step by step (explicitly praised the `make px4_sitl gz_x500` root), not flat file trees.
- User's mental model to preserve: `:=` = immediate expansion; `$@_default` restores the full target; `--build` selects the existing build dir (does NOT re-select `.px4board`); `--` separates CMake args from Ninja args; `gz_x500` is a Ninja target, not a Make target.
- Hardware facts (teammate-supplied): FMU = STM32H743VIT6 + STM32F103C8T6, ICM-42688-P (SPI1), IST8310 (I2C4), SPA06-003 (I2C2), H104 external gyro (CAN1/USART1), SIT3051TK ×2 CAN transceivers, SY8303 + TLV75533. ESC = STM32G071GBU6N + FD6288Q (250V 3-phase, 200ns dead-time, +1.5A/-1.8A) + INA240A1 (20V/V) + WS2812B.
- Key sensor specs: ICM-42688-P gyro noise 2.8 mdps/√Hz, accel 70 µg/√Hz, SPI 24MHz, 2KB FIFO; SPA06 128x oversample ≈0.5 Pa RMS; IST8310 I2C addr 0x0E.
- Missing datasheets (ask hardware teammate): IST8310, SPA06-003, SY8303.
- Motor selection: 2S battery, budget ¥120–150/4. Recommendation = LannRC 1404 4600KV + 2.5寸 3叶桨 for a 200–249g target; 1203 5500KV insufficient for 249g; must confirm motors support 2S (KV alone insufficient).
- 249g rule means every 5g counts; 桨保 envelope constrains prop size to ~2.5寸.
- Research conclusion: RM2027 drone tasks resemble loitering-munition/interceptor roles; UWB requires pre-placed ground anchors (likely not permitted) so fallback = 光流 + ToF + IMU + 气压 (relative only) or ground-camera/radar external position via `VISION_POSITION_ESTIMATE`.
- H7 flash verification is partially done and now de-prioritized per user ("我已经验证了一时期了…f103是找过线，也先不用验证了").
