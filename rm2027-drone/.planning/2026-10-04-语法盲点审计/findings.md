# findings：语法盲点审计

## 方法
扫 43 篇的代码块 + 关键词，按"偏离裸机 C + CubeMX 经验的距离"分档。

## 初步判断（待扫描后校正）
可能不会的候选：
- **GNU Make 的 eval/call/patsubst** —— 已补（Makefile.md §6）；但 **Make 的其它构造**还没查
- **CMake 的生成期魔法**：`px4_add_module` / `px4_add_library` / `configure_file` / 自定义命令
- **Kconfig 语言**：`.px4board` 的 `CONFIG_X=y` 怎么变成宏与参数（菜单/依赖/默认值）
- **链接脚本**：`MEMORY` / `SECTIONS` / `KEEP` / `PROVIDE` / `ASSERT`
- **NuttX 特有**：`CONFIG_*` 命名族、`task_spawn`、`boardctl`、`nsh` 命令注册
- **C 侧魔法**：宏字符串化/拼接、`__EXPORT`、`__attribute__((constructor))`、section 属性、`extern "C"`
- **uORB 宏**：`ORB_DECLARE/ORB_DEFINE`、`.msg` → 生成代码、`Subscription`/`Publication`
- **启动汇编**：向量表、`Reset_Handler`、`.data` 搬运、`__libc_init_array`
- **shell**：`sed` 那串管道（Makefile:237 已讲）、`git clean -dXfq` 各参数

## 扫描后的结论（数据驱动）
代码块内语法分布（183 块 / 1622 行）：
  CMake 51 · GNU Make 40 · uORB/PX4 26 · C 宏 12 · shell 11 · 汇编 7 · Kconfig 5 · 链接脚本 3

Top 6 要补（陌生度 × 频率）：
  1. uORB/PX4 框架宏与类（ModuleBase / task_spawn / Subscription / wq_configurations）
  2. GNU Make 剩余构造（define / $(shell) / $(if) / $(foreach) / $@ $< $^）
  3. CMake 生成期（★ function() vs macro() 作用域差异是最大坑）
  4. NuttX CONFIG_* 命名族（与 Kconfig 语言是两回事）
  5. PX4 的 C 宏（__EXPORT / __attribute__ / # 与 ## 规则）
  6. 启动汇编与 C 运行时初始化（Reset_Handler / __libc_init_array / .data 搬运）

5 条需"改"而不只是"补"：
  ① 03_moc 里的逐行语法细节下沉到 02 层（Makefile 已做，CMakeLists 待做）
  ② 134 个代码块没标语言 ⇒ 补 ```cmake / ```make / ```sh
  ③ 裸文件名歧义（全仓 2433 个 CMakeLists.txt）⇒ 首次给全路径
  ④ 02_code_twin/build/ 缺 CMakeLists.md
  ⑤ 机器路径扫尾（已基本完成）

## A′ 的新发现
- **三份 uORB.h，ORB_DEFINE 参数个数不同**：platforms/common(6 参，本板用) / ros2(5 参) / NuttX apps(3 参)
  ⇒ 判据：`__orb_##name` 前缀 ⇒ common 或 ros2 版；`g_orb_##name` ⇒ NuttX 版
- **.msg → 生成【两半】**：`uORB/topics/<name>.h`（结构体+ORB_DECLARE）+ `msg/topics_sources/<name>.cpp`（ORB_DEFINE）
- **`uint8 ORB_QUEUE_LENGTH = 8` 不是字段** ⇒ 变成 `#define …_ORB_QUEUE_LENGTH 8`
- **`struct __EXPORT sensor_gyro_s`** —— 审计里那条"PX4 的 C 宏"__EXPORT 就出现在这里（待写的 c-macros 篇有实例了）
