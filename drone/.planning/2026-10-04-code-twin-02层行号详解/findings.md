# findings：code-twin 02 层行号详解

## 已确认
- **用户举的例子 `Makefile:237`**：
  `ALL_CONFIG_TARGETS := $(shell find boards -maxdepth 3 -mindepth 3 -name '*.px4board' -print | sed …)`
  ⇒ 板名是**扫出来的**，不是写死的；扫到 `boards/rm2027/fmu-h743/default.px4board`
  → 去 `boards/`、去 `.px4board`、`/`→`_` ⇒ `rm2027_fmu-h743_default`
- `Makefile:244-245` ⇒ `$(ALL_CONFIG_TARGETS): @$(call cmake-build,$@$(BUILD_DIR_SUFFIX))`
- `Makefile:248-250` ⇒ 额外规则：`%_default` 可省略后缀（`CONFIG_TARGETS_DEFAULT`）
- **结论**：新增一块板 = 新增 `boards/<vendor>/<model>/default.px4board`，`make <vendor>_<model>_default` 自动可用，**不用改 Makefile**
- **源码根的教训**（上一轮）：路径只维护在 `tools/source-root.conf`，工具统一 `from _root import source_root`

## 待确认
- Makefile 那 5 步 `cmake-build` 宏的完整展开（用户贴到 1.2(B) 就停了）
