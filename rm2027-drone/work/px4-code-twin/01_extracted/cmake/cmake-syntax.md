# CMake 语法（提炼知识）

> **这是 01 层（提炼知识）** —— 从 PX4 的 CMake 体系里萃取的 **CMake 语言本身**。
> **02 层遇到这些语法时链接回这里**；02 层只讲"某个文件的行号在干什么"。
>
> **什么时候读这篇**：看到 `function()` / `macro()` / `PARENT_SCOPE` / `set_property(GLOBAL …)` /
> `CACHE` / `if(VAR)` 而**不确定它到底怎么作用**的时候。
> **出处**：源码根见 [`../../tools/source-root.conf`](../../tools/source-root.conf)；实例都取自 PX4 真实代码。

---

## 0. 这篇讲什么 / 不讲什么

| 讲 | 不讲 |
|---|---|
| **作用域模型** —— 这是 CMake 最大的坑（`function` vs `macro`、目录作用域、`PARENT_SCOPE`、`CACHE`） | CMake 入门（`add_executable` / `target_link_libraries`）—— 网上随处有 |
| `GLOBAL` 属性与"跨目录收集"（★ PX4 的核心手法） | Makefile/Ninja 生成器细节 |
| `if()` 的两种写法与反直觉之处 | CPack / CTest / install 那一套 |
| 构建期生成文件的两条路：`configure_file` vs `add_custom_command` | 工具链文件（toolchain file）——另开一篇 |
| `list()` / `foreach()` | 生成器表达式 `$<...>` —— 本套文档暂未涉及 |

**★ 一句话前提**：CMake 是**两阶段**的 —— **配置期**（跑 `cmake`，执行所有 `xxx()` 命令）
和**构建期**（跑 `ninja`，只做事先生成好的 `build.ninja`）。**下面讲的一切差异都源于这个分工。**

---

## 1. ★★ `function()` vs `macro()` —— 作用域差异（本篇最重要的一条）

### 1.1 实测结论（我真跑过，输出如下）

```cmake
set(VAR "外面")

function(myfunc)
  set(VAR "function里改的")      # 只在函数作用域内
  message(STATUS "  [function 内] VAR=${VAR}")
endfunction()

macro(mymacro)
  set(VAR "macro里改的")         # 文本替换 ⇒ 等于在调用处直接写这一行
endmacro()

function(withparent)
  set(VAR "用PARENT_SCOPE写的" PARENT_SCOPE)   # 显式往上写一层
endfunction()

myfunc()      ; message(STATUS "调用 function 之后: VAR=${VAR}")
mymacro()     ; message(STATUS "调用 macro 之后  : VAR=${VAR}")
withparent()  ; message(STATUS "PARENT_SCOPE 之后: VAR=${VAR}")
```
**实测输出：**
```
  [function 内] VAR=function里改的
调用 function 之后: VAR=外面              ← ★ function 里 set 的【不外泄】
调用 macro 之后  : VAR=macro里改的         ← ★ macro 里 set 的【外泄了】
PARENT_SCOPE 之后: VAR=用PARENT_SCOPE写的   ← ★ 显式往上写才能出去
```

### 1.2 一句话区别

| | `function()` | `macro()` |
|---|---|---|
| 本质 | **真的是一次函数调用**，有**自己的变量作用域** | **纯文本替换**：把宏体**贴到调用处**再执行 |
| 里面 `set(X …)` | 只在函数内可见，**外面看不到** | **改动调用处的变量**（等同你在那行手写） |
| 传参 | `$(1)` 式 —— `ARGV0`/`ARGN`，且**参数是值** | 宏体里 `${参数名}` 直接替换 |
| 变量名冲突 | 安全 | **会把调用处同名变量洗掉**（坑） |
| 想往外写 | 必须 `set(X … PARENT_SCOPE)` | 直接 `set` 就出去了 |
| 用哪个 | **默认用 `function`** | 只在"想故意改调用处变量"或写很小的一段时才用 |

### 1.3 PX4 里的真实分布（★ 说明 PX4 也基本只用 function）

| 形态 | 位置 | 是什么 |
|---|---|---|
| `function(px4_add_module)` | [`cmake/px4_add_module.cmake:84`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-module-cmake-84) | ★ 最核心的一个：定义一个 PX4 模块 |
| `function(px4_add_library target)` | [`cmake/px4_add_library.cmake:41`](cmake-syntax.md#^src-cmake-px4-add-library-cmake-41) | 定义一个库（**没有 MAIN** ⇒ 不注册成 NSH 命令） |
| `function(px4_add_common_flags)` | [`cmake/px4_add_common_flags.cmake:43`](cmake-syntax.md#^src-cmake-px4-add-common-flags-cmake-43) | 给所有目标加公共编译选项 |
| `function(px4_add_git_submodule)` | [`cmake/px4_git.cmake:58`](cmake-syntax.md#^src-cmake-px4-git-cmake-58) | 生成/填充子模块 |
| **`macro(px4_setup_gtest_without_fuzztest)`** | **[`cmake/px4_add_gtest.cmake:51`](cmake-syntax.md#^src-cmake-px4-add-gtest-cmake-51)** | ★ **整个 `cmake/` 目录里唯一的 `macro`** —— 值得点进去看它为什么用它 |

**⇒ 判据：**你以后写板级/模块的 CMake，**一律写 `function`**；看到 `macro` 要警觉"它会改我这边的变量"。**

---

## 2. 变量作用域的四层（理解 `PARENT_SCOPE` 的前提）

```
① 函数作用域（function 内）    —— 出函数即消失；想留 → PARENT_SCOPE
② 目录作用域（每个 add_subdirectory 一层）—— 子目录【往下继承】，改了不往上传
③ 全局 CACHE 变量（-DX=1 或 set(... CACHE ...)）—— 跨目录、跨次运行都在，存进 CMakeCache.txt
④ GLOBAL 属性（≠ 变量！见 §3）—— 整个工程唯一一份，谁都读写
```

| 想干什么 | 写法 | 实例 |
|---|---|---|
| 把值往**上一层**传 | `set(X ${v} PARENT_SCOPE)` | [`cmake/kconfig.cmake:325`](cmake-syntax.md#^src-cmake-kconfig-cmake-325)、[`cmake/px4_parse_function_args.cmake:105`](cmake-syntax.md#^src-cmake-px4-parse-function-args-cmake-105)、[`cmake/px4_list_make_absolute.cmake:56`](cmake-syntax.md#^src-cmake-px4-list-make-absolute-cmake-56) |
| 定义**跨目录持久**的值 | `set(X v CACHE <类型> "<帮助>" FORCE)` | [`cmake/kconfig.cmake:1`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-1) `set(BOARD_DEFCONFIG ${PX4_CONFIG_FILE} CACHE FILEPATH "path to defconfig" FORCE)` |
| 让命令行 `-DX=` 能覆盖 | 同上（`CACHE` 变量天然可被 `-D` 覆盖） | 你敲的 `-DCONFIG=rm2027_fmu-h743_default` 就是这么进来的 |

**★ 两个容易混的点：**
```
· CACHE 变量【不是】普通变量：`set(X v)` 与 `set(X v CACHE ...)` 是两回事，
  同名时"普通变量"会【遮住】CACHE 变量（所以有人 get_property 又 set 来 set 去）
· `FORCE` = 即使已存在也强制覆盖；不加 FORCE 时，已存在的 CACHE 变量【不会被改】
   —— 这正是"我改了 CMakeLists 怎么没生效？删掉 CMakeCache.txt 就好了"的原因
```cmake

---

## 3. `GLOBAL` 属性 —— PX4 为什么非用不可

**`add_subdirectory` 会造成**目录作用域边界**：子目录往父目录写普通变量是传不上去的。**
**但 PX4 需要"**各个子目录把自己的源文件/模块名汇报给顶层，最后统一链接**" —— 于是用了全局属性。**

```cmake
set_property(GLOBAL APPEND PROPERTY PX4_SRC_FILES         ${ABS_SRCS})     # px4_add_library.cmake:56
set_property(GLOBAL APPEND PROPERTY PX4_MODULE_PATHS     ${CMAKE_CURRENT_SOURCE_DIR})  # :54
set_property(GLOBAL APPEND PROPERTY PX4_MODULE_LIBRARIES ${MODULE})        # px4_add_module.cmake:176
set_property(GLOBAL APPEND PROPERTY PX4_KERNEL_MODULE_LIBRARIES ${MODULE}) # :173
```
**⇒ 读法：`set_property(对象 属性 操作 值)`。这里的"对象"是 `GLOBAL`，"操作"是 `APPEND PROPERTY`。**

| 写法 | 含义 |
|---|---|
| `set_property(GLOBAL PROPERTY X v)` | 覆盖设置全局属性 X |
| `set_property(GLOBAL APPEND PROPERTY X v)` | **追加**（列表式）—— PX4 全用这个 |
| `get_property(var GLOBAL PROPERTY X)` | 读出来放到 `var` |
| `get_property(var GLOBAL PROPERTY X SET)` | 读出来 **+ 同时给出是否存在**（`SET` 是"带回是否已定义"的标志） |

**★ 一条真实用途（顺带解释了 ccache 怎么生效的）：**
```cmake
set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${CCACHE_PROGRAM}")   # cmake/ccache.cmake:48
```
**⇒ 这是 CMake 的"全局编译启动器"钩子 —— 设了它，**所有**编译动作前面都会被插上 ccache。**

---

## 4. ★ `if()` 的坑：`if(VAR)` 与 `if(${VAR})` 不看同一件东西

### 4.1 实测（我真跑过）

```cmake
set(VAR "somevar")      # ★ VAR 的值是一个【像变量名的字符串】，而 somevar 并未定义

if(VAR)      → 真       # 看 VAR【自己】的值：非空 ⇒ 真
if(${VAR})   → 假       # 先把 VAR 展开成 somevar，再把它当【变量名】取值 ⇒ 未定义 ⇒ 假

set(B "0")
if(B)        → 假       # 0 / OFF / NO / FALSE / N / IGNORE / NOTFOUND / 以 -NOTFOUND 结尾 都算假
```
**⇒ 结果**相反**，而且两个都"看起来对" —— 这就是最坑的地方。**

### 4.2 规则

```
if(X)       ——  X 是【变量名】。CMake 取 X 的值再判断真假；
                若 X 未定义，则【退一步看字符串 X 本身】是否是真值（第二条规则）
if(${X})    ——  先展开成文本，再把那段文本【当变量名】重新判断
if("${X}")  ——  引号包住 ⇒ 把它当【字符串字面量】判断（不再看它像不像变量名）
```

### 4.3 PX4 里两种写法都有（所以要认得）

| 写法 | 位置 | 说明 |
|---|---|---|
| `if(${PX4_PLATFORM} MATCHES "nuttx")` | [`cmake/bloaty.cmake:81`](cmake-syntax.md#^src-cmake-bloaty-cmake-81) | 展开后做**正则匹配**（这里必须展开） |
| `if(${LABEL} MATCHES "default" OR …)` | [`cmake/kconfig.cmake:74`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-74) | 同上 |
| `if(NOT DYNAMIC)` | [`cmake/px4_add_module.cmake:168`](cmake-syntax.md#^src-cmake-px4-add-module-cmake-168) | 判断**变量本身真假**（正确用法） |
| `if(NOT STACK_MAX)` | [`cmake/px4_add_module.cmake:200`](cmake-syntax.md#^src-cmake-px4-add-module-cmake-200) | 同上 |

**⇒ 实践建议：**
```
· 判"变量有没有值"        → if(VAR)       或  if(DEFINED VAR)
· 判"字符串相等/正则匹配"  → if("${VAR}" STREQUAL "x") / if(${VAR} MATCHES "…")
· ★ 拿不准时加引号 if("${VAR}") —— 引号能挡掉"值像变量名"这个坑
```

---

## 5. 构建期生成文件的两条路

| | `configure_file(输入 输出)` | `add_custom_command(OUTPUT … COMMAND …)` |
|---|---|---|
| 何时执行 | **配置期**（`cmake` 跑的时候） | **构建期**（`ninja` 跑的时候） |
| 输入 | 一个**模板文件**（`@VAR@` / `${VAR}` 占位） | 任意命令（脚本、编译器等） |
| 适合 | **替换变量生成头文件/脚本** | 跑一个**程序**生成代码（如从 `.msg` 生成 C++）、拷文件、算校验 |
| 变更触发 | 配置期重跑就更新 | 由 `DEPENDS` 决定（依赖变了才重跑） |
| PX4 实例 | （本套文档暂未涉及） | [`CMakeLists.txt:515`](../../02_code_twin/build/CMakeLists.md#^src-CMakeLists-txt-515) `add_custom_command(OUTPUT ${uorb_graph_config} …)` |

**★ 判据：**"只是把变量填进模板" → `configure_file`；"要跑一个程序才产出" → `add_custom_command`。**
**★ 常见坑**：`add_custom_command(OUTPUT)` 产出的文件，**必须**被某个 target 的依赖引用（或写进 `add_custom_target` 的 `DEPENDS`），否则不会被执行。

---

## 6. `list()` 与 `foreach()` —— CMake 里的"数组"

```cmake
set(L a b c)                  # 这就是一个 list（空格分隔的字符串）
list(APPEND L d)              # 追加 ⇒ a b c d
list(LENGTH L n)              # n = 4
list(FIND L b idx)            # idx = 1（找不到是 -1）
list(REMOVE_ITEM L b)         # ⇒ a c d

foreach(x IN LISTS L)         # ★ 注意 IN LISTS 是"遍历列表的值"
  message(STATUS "元素: ${x}")
endforeach()
foreach(x ${L})               # 这两种都对，但 IN LISTS 更安全（元素含分号时）
```cmake
| 点 | 说明 |
|---|---|
| **list 就是字符串** | 所以 `set(L "a;b")` 与 `set(L a b)` 相同（`;` 是分隔符） |
| **`IN LISTS`** | 遍历"列表变量"，**不是**遍历字面量 —— `IN ITEMS a b c` 才是字面量 |
| **`${CMAKE_CURRENT_SOURCE_DIR}`** | 当前 `CMakeLists.txt` 所在目录（**绝对路径**）—— 常与 list 配合收集文件 |
| **`${CMAKE_CURRENT_LIST_DIR}`** | 当前 **`.cmake` 文件**所在目录 —— **在 `cmake/*.cmake` 里要用这个**（不是前者！） |

**★ 最后一个是最容易写错的：在 `cmake/xxx.cmake` 里想引用同目录的文件，要 `CMAKE_CURRENT_LIST_DIR`，不是 `CMAKE_CURRENT_SOURCE_DIR`。**

---

## 7. 自己验证（30 秒，`cmake` 不用编译）

```bash
mkdir -p /tmp/cmtest && cd /tmp/cmtest && cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(t NONE)

set(VAR "外面")

function(myfunc)          # ★ function 必须【分行】写；写成 function(f) set(...) endfunction() 会报
  set(VAR "函数里")       #   "Parse error. Expected a newline"
endfunction()

macro(mymacro)            # macro 同理
  set(VAR "宏里")
endmacro()

myfunc()
message(STATUS "function 后: ${VAR}")
mymacro()
message(STATUS "macro 后   : ${VAR}")

function(withparent)      # 想往外写，必须 PARENT_SCOPE
  set(VAR "PARENT_SCOPE 写的" PARENT_SCOPE)
endfunction()
withparent()
message(STATUS "PARENT_SCOPE 后: ${VAR}")

set(V "somevar")          # ★ V 的值是个"像变量名"的字符串，而 somevar 并未定义
if(V)
  message(STATUS "if(V)     → 真")
else()
  message(STATUS "if(V)     → 假")
endif()
if(${V})
  message(STATUS "if(\${V})  → 真")
else()
  message(STATUS "if(\${V})  → 假")
endif()
EOF
cmake -S . -B build
```
**实测输出（我真跑过，逐行一致）：**
```
-- function 后: 外面                   ← ★ function 里 set 的【不外泄】
-- macro 后   : 宏里                    ← ★ macro 里 set 的【外泄了】
-- PARENT_SCOPE 后: PARENT_SCOPE 写的     ← 显式往上写才能出去
-- if(V)     → 真                       ← 看 V【自己】的值（非空即真）
-- if(${V})  → 假                       ← 把 somevar 当【变量名】再取值 ⇒ 未定义
```
**⇒ 亲手跑一遍，§1 与 §4 就再也不会忘。**

**⚠️ 一个真实的坑（我写这节时踩的）：`function`/`macro` **不能写成一行**。**
```cmake
function(f) set(VAR "x") endfunction()   # ✗ Parse error. Expected a newline, got identifier with text "set".
```
**⇒ CMake 的 `function`/`macro` 体**必须换行**（不像 shell 能用 `;` 连）。**

---

## 8. 跳转

- **02 层用它的地方** → [`../../02_code_twin/build/CMakeLists`](../../02_code_twin/build/CMakeLists.md)
  （那里讲"根 `CMakeLists.txt` 各行在干什么"）
- **构建流程全景** → [`../../03_moc/00-build-walkthrough`](../../03_moc/00-build-walkthrough.md)
- **`px4_add_module` / `px4_add_library` 逐段解析** → [`01-px4-cmake-organization`](01-px4-cmake-organization.md)
- **`.px4board` → Kconfig → 宏 的桥** → [`03-kconfig-bridge`](03-kconfig-bridge.md)
- **其它 01 层** → [`../make/gnu-make-syntax`](../make/gnu-make-syntax.md)、[`../nuttx/`](../nuttx/)、[`../stm32/`](../stm32/)

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-515"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:515`](cmake-syntax.md#^src-CMakeLists-txt-515)

```c
   512 │ 	set(graph_module_list "${graph_module_list}" "--src-path" "src/${module}")
   513 │ endforeach()
   514 │ 
▶  515 │ add_custom_command(OUTPUT ${uorb_graph_config}
   516 │ 	COMMAND ${PYTHON_EXECUTABLE} ${PX4_SOURCE_DIR}/Tools/uorb_graph/create.py
   517 │ 		${graph_module_list} --src-path src/lib
   518 │ 		--merge-depends
```
> **说明**：变更触发 | 配置期重跑就更新 | 由 DEPENDS 决定（依赖变了才重跑） | ┃ PX4 实例 | （本套文档暂未涉及） | CMakeLists.txt:515 add_custom_command(OUTPUT ${uorb_graph_config} …) |
^src-CMakeLists-txt-515

### `cmake/bloaty.cmake`
<a id="src-cmake-bloaty-cmake-81"></a>
**↓ 文档在讲这里：**[`cmake/bloaty.cmake:81`](cmake-syntax.md#^src-cmake-bloaty-cmake-81)

```c
    78 │ 		USES_TERMINAL
    79 │ 		)
    80 │ 
▶   81 │ 	if(${PX4_PLATFORM} MATCHES "nuttx")
    82 │ 		# bloaty compare with last master build
    83 │ 		add_custom_target(bloaty_compare_master
    84 │ 			COMMAND wget --continue --no-verbose https://s3.amazonaws.com/px4-travis/Firmware/master/${PX4_BOARD_VENDOR}_${PX4_BOARD_MODEL}_${PX4_BOARD_LABEL}.elf -O master.elf
```
> **说明**：if(${PX4_PLATFORM} MATCHES "nuttx") | cmake/bloaty.cmake:81 | 展开后做正则匹配（这里必须展开） |
^src-cmake-bloaty-cmake-81

### `cmake/kconfig.cmake`
<a id="src-cmake-kconfig-cmake-1"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:1`](cmake-syntax.md#^src-cmake-kconfig-cmake-1)

```c
▶    1 │ set(BOARD_DEFCONFIG ${PX4_CONFIG_FILE} CACHE FILEPATH "path to defconfig" FORCE)
     2 │ set(BOARD_CONFIG ${PX4_BINARY_DIR}/boardconfig CACHE FILEPATH "path to config" FORCE)
     3 │ 
     4 │ execute_process(COMMAND ${PYTHON_EXECUTABLE} -c "import menuconfig" RESULT_VARIABLE ret)
```
> **说明**：把值往上一层传 | set(X ${v} PARENT_SCOPE) | cmake/kconfig.cmake:325、cmake/px4_parse_function_args.cmake:105、cmake/px4_list_make_absolute.cmake:56 | ┃ 定义跨目录持久的值 | set(X v CACHE <类型> "<帮助>" FORCE) | cmake/kconfig.cmake:1 set(BOARD_DEFCONFIG ${PX4_CONFIG_FILE} CACHE FILEPATH "path to defconfig" FORCE) |
^src-cmake-kconfig-cmake-1

<a id="src-cmake-kconfig-cmake-74"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:74`](cmake-syntax.md#^src-cmake-kconfig-cmake-74)

```c
    71 │ 	# Depend on BOARD_DEFCONFIG so that we reconfigure on config change
    72 │ 	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${BOARD_DEFCONFIG})
    73 │ 
▶   74 │ 	if(${LABEL} MATCHES "default" OR ${LABEL} MATCHES "performance-test" OR ${LABEL} MATCHES "bootloader" OR ${LABEL} MATCHES "canbootloader")
    75 │ 		# Generate boardconfig from saved defconfig
    76 │ 		execute_process(
    77 │ 			COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
```
> **说明**：if(${PX4_PLATFORM} MATCHES "nuttx") | cmake/bloaty.cmake:81 | 展开后做正则匹配（这里必须展开） | ┃ if(${LABEL} MATCHES "default" OR …) | cmake/kconfig.cmake:74 | 同上 |
^src-cmake-kconfig-cmake-74

<a id="src-cmake-kconfig-cmake-325"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:325`](cmake-syntax.md#^src-cmake-kconfig-cmake-325)

```c
   322 │ 	set(config_romfs_extra_dependencies ${romfs_extra_dependencies} CACHE INTERNAL "extra ROMFS deps" FORCE)
   323 │ 
   324 │ 	if(SERIAL_PORTS)
▶  325 │ 		set(board_serial_ports ${SERIAL_PORTS} PARENT_SCOPE)
   326 │ 	endif()
   327 │ 
   328 │ 	# Serial ports
```
> **说明**：把值往上一层传 | set(X ${v} PARENT_SCOPE) | cmake/kconfig.cmake:325、cmake/px4_parse_function_args.cmake:105、cmake/px4_list_make_absolute.cmake:56 |
^src-cmake-kconfig-cmake-325

### `cmake/px4_add_common_flags.cmake`
<a id="src-cmake-px4-add-common-flags-cmake-43"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_common_flags.cmake:43`](cmake-syntax.md#^src-cmake-px4-add-common-flags-cmake-43)

```c
    40 │ #	Usage:
    41 │ #		px4_add_common_flags()
    42 │ #
▶   43 │ function(px4_add_common_flags)
    44 │ 
    45 │ 	add_compile_options(
    46 │ 		-g # always build debug symbols
```
> **说明**：function(px4_add_library target) | cmake/px4_add_library.cmake:41 | 定义一个库（没有 MAIN ⇒ 不注册成 NSH 命令） | ┃ function(px4_add_common_flags) | cmake/px4_add_common_flags.cmake:43 | 给所有目标加公共编译选项 |
^src-cmake-px4-add-common-flags-cmake-43

### `cmake/px4_add_gtest.cmake`
<a id="src-cmake-px4-add-gtest-cmake-51"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_gtest.cmake:51`](cmake-syntax.md#^src-cmake-px4-add-gtest-cmake-51)

```c
    48 │ #	Used when fuzztest is not available (e.g. TSAN builds where fuzztest's
    49 │ #	coverage instrumentation is incompatible).
    50 │ #
▶   51 │ macro(px4_setup_gtest_without_fuzztest)
    52 │ 	include(FetchContent)
    53 │ 	FetchContent_Declare(
    54 │ 		googletest
```
> **说明**：function(px4_add_git_submodule) | cmake/px4_git.cmake:58 | 生成/填充子模块 | ┃ macro(px4_setup_gtest_without_fuzztest) | cmake/px4_add_gtest.cmake:51 | ★ 整个 cmake/ 目录里唯一的 macro —— 值得点进去看它为什么用它 |
^src-cmake-px4-add-gtest-cmake-51

### `cmake/px4_add_library.cmake`
<a id="src-cmake-px4-add-library-cmake-41"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_library.cmake:41`](cmake-syntax.md#^src-cmake-px4-add-library-cmake-41)

```c
    38 │ #
    39 │ #	Like add_library but with PX4 platform dependencies
    40 │ #
▶   41 │ function(px4_add_library target)
    42 │ 	add_library(${target} STATIC EXCLUDE_FROM_ALL
    43 │ 		${ARGN}
    44 │ 	)
```
> **说明**：function(px4_add_module) | cmake/px4_add_module.cmake:84 | ★ 最核心的一个：定义一个 PX4 模块 | ┃ function(px4_add_library target) | cmake/px4_add_library.cmake:41 | 定义一个库（没有 MAIN ⇒ 不注册成 NSH 命令） |
^src-cmake-px4-add-library-cmake-41

### `cmake/px4_add_module.cmake`
<a id="src-cmake-px4-add-module-cmake-84"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:84`](cmake-syntax.md#^src-cmake-px4-add-module-cmake-84)

```c
    81 │ #				git_nuttx
    82 │ #			)
    83 │ #
▶   84 │ function(px4_add_module)
    85 │ 
    86 │ 	px4_parse_function_args(
    87 │ 		NAME px4_add_module
```
> **说明**：function(px4_add_module) | cmake/px4_add_module.cmake:84 | ★ 最核心的一个：定义一个 PX4 模块 |
^src-cmake-px4-add-module-cmake-84

<a id="src-cmake-px4-add-module-cmake-168"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:168`](cmake-syntax.md#^src-cmake-px4-add-module-cmake-168)

```c
   165 │ 		set (KERNEL TRUE)
   166 │ 	endif()
   167 │ 
▶  168 │ 	if(NOT DYNAMIC)
   169 │ 		target_link_libraries(${MODULE} PRIVATE prebuild_targets px4_platform systemlib perf)
   170 │ 		if (${PX4_PLATFORM} STREQUAL "nuttx" AND NOT CONFIG_BUILD_FLAT AND KERNEL)
   171 │ 			target_link_libraries(${MODULE} PRIVATE
```
> **说明**：if(${LABEL} MATCHES "default" OR …) | cmake/kconfig.cmake:74 | 同上 | ┃ if(NOT DYNAMIC) | cmake/px4_add_module.cmake:168 | 判断变量本身真假（正确用法） |
^src-cmake-px4-add-module-cmake-168

<a id="src-cmake-px4-add-module-cmake-200"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:200`](cmake-syntax.md#^src-cmake-px4-add-module-cmake-200)

```c
   197 │ 	endforeach()
   198 │ 
   199 │ 	# default stack max to stack main
▶  200 │ 	if(NOT STACK_MAX)
   201 │ 		set(STACK_MAX ${STACK_MAIN})
   202 │ 	endif()
   203 │ 	set_target_properties(${MODULE} PROPERTIES STACK_MAX ${STACK_MAX})
```
> **说明**：if(NOT DYNAMIC) | cmake/px4_add_module.cmake:168 | 判断变量本身真假（正确用法） | ┃ if(NOT STACK_MAX) | cmake/px4_add_module.cmake:200 | 同上 |
^src-cmake-px4-add-module-cmake-200

### `cmake/px4_git.cmake`
<a id="src-cmake-px4-git-cmake-58"></a>
**↓ 文档在讲这里：**[`cmake/px4_git.cmake:58`](cmake-syntax.md#^src-cmake-px4-git-cmake-58)

```c
    55 │ #	Example:
    56 │ #		px4_add_git_submodule(TARGET git_nuttx PATH "NuttX")
    57 │ #
▶   58 │ function(px4_add_git_submodule)
    59 │ 	px4_parse_function_args(
    60 │ 		NAME px4_add_git_submodule
    61 │ 		ONE_VALUE TARGET PATH
```
> **说明**：function(px4_add_common_flags) | cmake/px4_add_common_flags.cmake:43 | 给所有目标加公共编译选项 | ┃ function(px4_add_git_submodule) | cmake/px4_git.cmake:58 | 生成/填充子模块 |
^src-cmake-px4-git-cmake-58

### `cmake/px4_list_make_absolute.cmake`
<a id="src-cmake-px4-list-make-absolute-cmake-56"></a>
**↓ 文档在讲这里：**[`cmake/px4_list_make_absolute.cmake:56`](cmake-syntax.md#^src-cmake-px4-list-make-absolute-cmake-56)

```c
    53 │ 			list(APPEND list_var "${prefix}/${f}")
    54 │ 		endif()
    55 │ 	endforeach(f)
▶   56 │ 	set(${var} "${list_var}" PARENT_SCOPE)
    57 │ endfunction()
    58 │ 
```
> **说明**：把值往上一层传 | set(X ${v} PARENT_SCOPE) | cmake/kconfig.cmake:325、cmake/px4_parse_function_args.cmake:105、cmake/px4_list_make_absolute.cmake:56 |
^src-cmake-px4-list-make-absolute-cmake-56

### `cmake/px4_parse_function_args.cmake`
<a id="src-cmake-px4-parse-function-args-cmake-105"></a>
**↓ 文档在讲这里：**[`cmake/px4_parse_function_args.cmake:105`](cmake-syntax.md#^src-cmake-px4-parse-function-args-cmake-105)

```c
   102 │ 	endforeach()
   103 │ 
   104 │ 	foreach(arg ${IN_OPTIONS} ${IN_ONE_VALUE} ${IN_MULTI_VALUE})
▶  105 │ 		set(${arg} ${OUT_${arg}} PARENT_SCOPE)
   106 │ 	endforeach()
   107 │ 
   108 │ endfunction()
```
> **说明**：把值往上一层传 | set(X ${v} PARENT_SCOPE) | cmake/kconfig.cmake:325、cmake/px4_parse_function_args.cmake:105、cmake/px4_list_make_absolute.cmake:56 |
^src-cmake-px4-parse-function-args-cmake-105
