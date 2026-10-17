# progress：语法盲点审计

| 时间 | 做了什么 |
|---|---|
| 起步 | 按 skill 落盘 task_plan / findings / progress；下一步：扫 43 篇代码块 |
| 续 | ✅ 扫 43 篇（代码块 183 块 / 1622 行，排除标注层）按领域统计 |
| 续 | ✅ 校正两处误报：`##`（495 全是 markdown 标题）、`_start`（157 里大半是 nx_start/module_start） |
| 续 | ✅ 产出 `work/px4-code-twin/04_notes/语法盲点审计.md`（Top6 优先清单 + 分领域审计表 + 6 条待补 + 5 条需改 + 明确不补的） |
| 纠偏 | 用户指出：语法讲解放错了层（应在 01_extracted，不该塞在 02 篇尾）⇒ 已写入 task_plan 的"纠偏"节，按 0-A~0-D 执行 |
| B′ | ✅ `01_extracted/cmake/cmake-syntax.md`（CMake 语言：★function vs macro 作用域【实测证明】/ 变量四层作用域 / GLOBAL 属性 / ★if(VAR) vs if(${VAR})【实测证明结果相反】/ configure_file vs add_custom_command / list 与 CMAKE_CURRENT_LIST_DIR 的坑） |
| B′ | ✅ `02_code_twin/build/CMakeLists.md`（根 CMakeLists 行号详解：★project() 在 :242 前 240 行都在算板子 / 板名十条链 -DCONFIG→RM2027_FMU_H743 / include 顺序=依赖顺序 / GLOBAL 属性读取点） |
| B′ | 验证：19 个 CMake 行号逐条命中 + px4_add_common_flags.cmake:196 一字不差；链接 2095 条全可达；无重复段 |
| A′ | ✅ `01_extracted/uorb/uorb-mechanism.md`（.msg→生成两半实测展示 / ★三份 uORB.h 宏签名不同的坑 / ORB_ID·ORB_DECLARE·ORB_DEFINE 逐字展开 / C API vs C++ 封装选型 / ★语义三条 last-value·拷贝·时间戳 / ModuleBase+WorkItem 五件套 / wq_configurations 全集 / 排查命令） |
| A′ | 验证：19 个行号逐条命中；链接全可达；无重复段 |
| C′ | ✅ `01_extracted/c/px4-c-macros.md`（__EXPORT/__PRIVATE 定义与出现处 / __BEGIN_DECLS / __attribute__ 最常撞 6 种按本仓出现次数排 / ★# 与 ## 的三个真实实例 board_common.h:808·param_macros.h:197·uORB.h:80 / ＃与##不展开参数的规则 / ##__VA_ARGS__ 逗号吞噬 / 高频小宏 / 自验） |
| C′ | 验证：预处理器实测（STR/XSTR/CAT + packed 5 vs 8）与文档一致；14 个行号全命中 |
| #5 | ✅ `01_extracted/stm32/startup-and-crt.md`（复位向量 arm_vectors.c:61-66 → __start() stm32_start.c:183 → .bss 清零:209 / .data 搬运:220-221 → nx_start():315；★链接脚本 AT > FLASH 的含义；_sdata/_edata/_eronly/_sbss/_ebss 逐个；栈堆从哪来；与 CubeMX 那套对照；现象↔原因表） |
| #5 | ⚠️ 自查抓到 3 处行号写错并修正：_eronly 175→174、AT > FLASH 184→187、} > AXI_SRAM 193→196 |
| #5 | 验证：19 个行号（含 3 处修正后）全部命中；链接全可达；无重复段 |
| 收尾 | ✅ 审计 §3 的 Top5 全部完成；§4 的 5 条中 ④⑤ 完成、② 完成（真代码 17 个）；剩余 ①（03_moc 语法下沉，Makefile/CMakeLists 已做）③（裸文件名给全路径，部分已做）⑥（Kconfig/链接脚本语法，按需） |
| 收尾 | 全套规模：50 篇 / 24042 行 / 2146 条可跳转源码链接 / 1049 处标注源码 |
| P1 | ✅ 2146 条 file:// 外链 → 站内跳转（新增 tools/anchorize-sources.py：782→1063 个锚点，2167 条链接改写，命中 99.7%；剩 7 条降级纯文本）。真·file:// 链接 = 0（仅 tools/README 2 处文字说明） |
| P5 | ✅ `01_extracted/cmake/px4-global-variables.md` —— 数据驱动分级：T1(PX4_SOURCE_DIR 141 次/…) vs ★T3 枢纽(CONFIG 5 次、PX4_BOARD_NAME 3 次、config_module_list 4 次)，并指出"引用少≠不重要"；含完整传递链与"改一个要连带检查什么" |
| 踩坑 | ① anchorize 默认干跑导致没生效 ⇒ 改为默认真写、--dry-run 才干跑 ② annotate 会【重建标注段⇒冲掉锚点】⇒ 在 annotate 头注释加警告 + tools/README 写明顺序 |
| 收尾 | 51 篇 / 25516 行 · 站内跳转 3257 条全可达 · 锚点 1063 · ``` 全配对 · 无重复段 |
