# GNU Make 语法（提炼知识）

> **这是 01 层（提炼知识）** —— 从 PX4 的 Makefile 里萃取出来的 **GNU Make 语言本身**。
> **02 层遇到这些语法时链接回这里**；02 层只讲"某个文件的行号在干什么"。
>
> **什么时候读这篇**：看到 `$(eval …)` / `$(call …)` / `$(patsubst …)` / `$$x` / `$@` 而不知道它怎么算的。
> **出处**：`Makefile`（源码根见 `tools/source-root.conf`）；实例都取自 PX4 真实代码。

---

## 0. 这篇讲什么 / 不讲什么

| 讲 | 不讲 |
|---|---|
| Make 的**两层时间**（解析期 / 执行期）—— 一切困惑的根 | Make 的入门（目标/依赖/basic 规则）—— 网上随处有 |
| `$(eval)` / `$(call)` / `$(patsubst)` / `$(shell)` / `$(if)` / `$(foreach)` | Make 的隐式规则、并行 `-j` 细节 |
| `define` 多行宏、`$(1)` 形参 | autotools / automake 那套 |
| 变量四种赋值（`:=` `=` `?=` `+=`）、`override` | 其他 make 方言（BSD make 等） |
| 自动变量 `$@ $< $^`、`$$` 转义 | — |

---

## 1. `$(eval ...)` / `$(call ...)` / `patsubst` 这一段（★ 从最难的一处起）

> **这一节是给"看不太懂 :183/:184 那两行"的人写的。** 看完再回去看那两行，就不神秘了。

### 1.0 先立地基：Make 有**两层时间**（所有困惑的总根源）

```
① 解析期（parse time）—— Make【读】Makefile 的时候
      · 变量赋值 (:=  =  ?=  +=) 在这里发生
      · $(...) 在这里【展开成文本】
      · 规则/目标的"骨架"在这里确定

② 执行期（recipe time）—— 真正跑某条规则的命令的时候
      · 每条 recipe 一行行交给 shell 去跑
      · $@ / $< / $^ 这类"自动变量"【这时才有值】
      · 一条 recipe 里的 $$ 才变成 shell 看到的 $
```

**⇒ 关键结论：**
```make
$(xxx)   → Make 展开一层（解析期或执行期，看写在哪）
$$(xxx)  → 让 Make 展开成 $(xxx) 交给 shell（shell 再展开）
★★★ 而 $(eval ...) 干的事是：让它里面的文本【重新回到解析期】被 Make 再读一遍。
     这就是它难懂的原因 —— 它在【执行期】触发了【解析期】的动作。
```

**一个最小例子（建议你自己拿 `make -f` 试）：**
```make
A := hello
$(eval B := $(A)-world)   # 解析期：eval 让 "B := hello-world" 被当成一行 Makefile 读进去
$(shell echo $(A)-$(B))   # 此时 A=hello, B=hello-world  ⇒ 打印 hello-hello-world
```make

---

### 1.1 逐个符号拆开

| 写法 | 名字 | 一句话 | 在本 Makefile 里的实例 |
|---|---|---|---|
| `$(X)` | 变量展开 | 取变量 X 的值 | `$(SRC_DIR)` |
| `$$(X)` | **转义** | Make 展开成字面 `$(X)`，留给 shell | recipe 里的 `$$prev`（shell 变量） |
| `$@` | **自动变量** | 当前**目标名** | `:245` 的 `$@` = `rm2027_fmu-h743_default` |
| `$<` `$^` | 自动变量 | 第一个依赖 / 全部依赖 | 本宏没用到 |
| `$(1)` `$(2)` … | **宏参数** | `call` 传进来的第 N 个参数 | `$(1)` = 目标名 |
| `$(call 宏, a, b)` | **调用宏** | 把 `define 宏` 的正文展开，`$(1)←a`, `$(2)←b` | `:245` `$(call cmake-build, 目标名)` |
| `$(patsubst 模式, 替换, 文本)` | **模式替换** | 把**每个词**按 `%` 模式改写 | `:183` 剥后缀 |
| `$(eval 文本)` | ★ **求值** | 把**展开后的结果**当成 Makefile 语法**再解析一次** | `:183` `:184` |
| `override` | **修饰符** | 即使命令行传了同名变量，也照样赋值 | `:183` `override CMAKE_ARGS +=` |
| `+=` | 追加 | 在变量后面接一段 | `:183` |
| `?=` | **条件赋值** | 只在**尚未定义**时赋值 | `:132` `CMAKE_ARGS ?=` |
| `:=` | 立即展开 | 右边**当场**算好再存 | `:123` `SRC_DIR :=` |
| `=` | 递归展开 | 存的是**式子**，**用的时候**才算 | （本宏里主要是 `:=` / `?=`） |
| 行首 `@` | 静默 | **不回显**这条命令 | recipe 里到处是 |

---

### 1.2 `$(call ...)` 怎么把 `$(1)` 传进去

**宏定义在 `:179`：**
```make
define cmake-build
	...
	$(eval override CMAKE_ARGS += -DCONFIG=$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1)))
	@$(eval BUILD_DIR = "$(SRC_DIR)/build/$(1)")
	...
endef
```
**调用在 `:245`：**
```make
$(ALL_CONFIG_TARGETS):
	@$(call cmake-build,$@$(BUILD_DIR_SUFFIX))
```

**⇒ 展开过程（本板、普通构建）：**
```
① $@                 = rm2027_fmu-h743_default
② $(BUILD_DIR_SUFFIX)= 空                 （来自 :129）
③ 拼起来传给宏      = rm2027_fmu-h743_default
④ 宏里 $(1)         = 就是它
```
**⇒ 若做变体构建（`BUILD_DIR_SUFFIX=_replay`，见 `:127`）：**
```
③ 传进去的 $(1)     = rm2027_fmu-h743_default_replay
④ :183 的 patsubst 负责把 _replay 剥掉 ⇒ 传 -DCONFIG=rm2027_fmu-h743_default（干净的板名）
④ :184 的 BUILD_DIR 却【保留】_replay ⇒ build/rm2027_fmu-h743_default_replay（变体有独立目录）
```make
**★ 这就是"同一个后缀，在一处剥掉、在另一处保留"的原因 —— 两份用途不同。**

---

### 1.3 `$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1))` 逐字拆

**`patsubst` 的三段：`$(patsubst 模式, 替换成, 文本)`。`%` 是通配符，匹配**任意一段**（这里习惯只写一个）。**

**设 `BUILD_DIR_SUFFIX = _replay`、`$(1) = rm2027_fmu-h743_default_replay`：**

| 步 | 求值 | 结果 |
|---|---|---|
| 先展开 `$(BUILD_DIR_SUFFIX)` | `%$(BUILD_DIR_SUFFIX)` → `%_replay` | 模式 = `%_replay` |
| 再展开 `$(1)` | 文本 = `rm2027_fmu-h743_default_replay` | — |
| 匹配 | `%` 吃掉 `rm2027_fmu-h743_default`，剩下 `_replay` 对上 | ✅ 命中 |
| 输出 | `%` 那部分原样搬到替换串 `%` 的位置 | **`rm2027_fmu-h743_default`** |

**⇒ 后缀就这么被剥掉了。**
**⇒ 若后缀为空（普通构建）：模式 = `%`，`%` 吃掉整个词 ⇒ 输出与输入相同 ⇒ **等于没变**（这正是它安全的地方）。**

**★ 两个容易错的点：**
```
· patsubst 是【按词】处理的（空格分隔），不是按字符 —— 传一句话进去会逐词替换
· 模式里没写 % 时 patsubst 只匹配"完全相等"的词（不是子串匹配）
```make

---

### 1.4 `$(eval ...)` 到底在干什么（★ 最难的一处）

**它分两步：**
```
第 1 步（普通展开）：把 $(...) 全部算成【文本】
第 2 步（★ 关键）  ：把这个文本【当成 Makefile 的一行】再解析一次
```
**⇒ 所以 `:183` 这一行实际上是"**用变量的值，动态地写出一行 Makefile 赋值语句**"。**

**逐层剥开 `:183`（本板、普通构建）：**
```make
$(eval override CMAKE_ARGS += -DCONFIG=$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1)))
```
```
① 算 $(1)                        → rm2027_fmu-h743_default
② 算 $(BUILD_DIR_SUFFIX)         → （空）
③ 算 $(patsubst %,...)           → rm2027_fmu-h743_default      （§1.3）
④ 拼出待求值文本                  → override CMAKE_ARGS += -DCONFIG=rm2027_fmu-h743_default
⑤ eval 把上面那串【当 Makefile 读】 → 于是 CMAKE_ARGS 变量被追加了一段 -DCONFIG=...
⑥ 结果：CMAKE_ARGS = <原来的值> -DCONFIG=rm2027_fmu-h743_default   （:132 起它本来是空的）
```

**⇒ `:184` 同理：**
```make
@$(eval BUILD_DIR = "$(SRC_DIR)/build/$(1)")
#  展开 → BUILD_DIR = "/home/.../build/rm2027_fmu-h743_default"
#  eval 把它当 Makefile 读 ⇒ BUILD_DIR 这个变量就有了值，供后面 :208-214 使用
```

**★ `override` 为什么在这里？**
```
用户可以在命令行传变量：make rm2027_fmu-h743_default CMAKE_ARGS=-DFOO=1
命令行变量默认【压过】Makefile 里的赋值 ⇒ 不加 override 的话，:183 的追加会被无视
override 让这次赋值始终生效 ⇒ 保证 -DCONFIG=<板名> 一定会传进 cmake
```

**★ 为什么非要用 `eval` 不可？（反面教材）**
```make
# ✗ 错误写法：只是算出一个字符串，什么都没有发生 —— CMAKE_ARGS 不会变
$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1))

# ✓ 正确写法：算出来之后【再让 Make 读一遍这行赋值】
$(eval override CMAKE_ARGS += -DCONFIG=$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1)))
```
**⇒ `eval` 的存在感就来自这个差别：**"算出文本" 和 "把文本当代码执行" 是两件事。****

---

### 1.5 顺带：`$(call cmake-cache-check)` 里全是同一套路（`:217-227`）

**看一眼就有"原来如此"的感觉 —— 四步全是 `eval` + `shell` + `patsubst` 的组合：**
```make
:220  $(eval CACHED_CMAKE_OPTIONS  = $(shell cd $(BUILD_DIR) && cmake -L | sed ...))   # 读缓存
:222  $(eval DESIRED_CMAKE_OPTIONS = $(shell echo $(CMAKE_ARGS) | sed ...))           # 读期望
:224  $(eval VERIFIED_... = $(foreach option,$(DESIRED_...),$(strip $(findstring ...))) # 逐个比对
:226  $(eval CMAKE_CACHE_CHECK = $(if $(findstring $(DESIRED_...),$(VERIFIED_...)),,y)) # 一致则留空
```
**⇒ 结论：`CMAKE_CACHE_CHECK` 非空 ⇒ 说明"缓存与期望不一致" ⇒ `:208` 的条件成立 ⇒ 重新 configure。**
**⇒ 这套"用 `eval` 在 recipe 执行期动态设变量、再在同一个 recipe 后面用"的写法，是这份 Makefile 的**核心技巧** —— 看懂 6.4 就全通了。**

---

### 1.6 自己验证的小实验（30 秒，不用编译）

```bash
cd <源码根>
cat > /tmp/t.mk <<'EOF'
SUF := _replay
ONE := rm2027_fmu-h743_default$(SUF)
$(eval FOO += -DCONFIG=$(patsubst %$(SUF),%,$(ONE)))
$(info [patsubst 结果] $(patsubst %$(SUF),%,$(ONE)))
$(info [eval 之后]    FOO=$(FOO))
$(info [$(1) 的宿主] call 传参：)
define m
$(info    call 收到 $(1))
endef
$(call m,XYZ)
EOF
make -f /tmp/t.mk
```
**预期输出：**
```
[patsubst 结果] rm2027_fmu-h743_default
[eval 之后]    FOO=-DCONFIG=rm2027_fmu-h743_default      ← 证明 eval 真的改了变量
   call 收到 XYZ                                          ← 证明 $(1) 来自 call 的第 1 个参数
```
```
（末尾 `make: *** 无目标。停止。` 是**正常的** —— 这个实验只有 `$(info ...)` 输出，没写 target。
  我要看的只是上面三行。）
```
**★ 上面这三行是【我真跑出来的】，不是我猜的** —— 你可以照着复现。

**⇒ 亲手跑一遍，1.3 / 1.4 就再也不会忘。**

---

---

---

## 2. `define` 多行宏 —— 和普通变量有什么不同

```make
# 普通变量：单行
A := hello

# define：可以多行，赋值给变量名
define GREET
	echo "line1"
	echo "line2"
endef
```
| 点 | 说明 |
|---|---|
| **内容多行** | `endef` 之前的所有行都是它的"值"（含换行） |
| **用在 recipe 里** | `$(GREET)` 展开后，**每一行都变成一条独立命令** |
| **`$(1)` `$(2)` …** | 只有在 **`$(call 名字, 参数…)`** 调用时才被替换 —— 这就是"Make 版函数" |
| **不调用也能用** | 直接 `$(GREET)` 展开，此时 `$(1)` 保持字面量（不是空，是原样） |

**⇒ PX4 里的例子**：[`Makefile:179`](../../02_code_twin/build/Makefile.md#^src-Makefile-179) 的 `define cmake-build`、[`Makefile:217`](gnu-make-syntax.md#^src-Makefile-217) 的 `define cmake-cache-check`。
**⇒ 它们的 `$(1)` 由 [`Makefile:245`](gnu-make-syntax.md#^src-Makefile-245) / `:250` 的 `$(call cmake-build, 目标名)` 传进来。**

---

## 3. `$(shell ...)` —— 解析期就执行 shell（★ 有代价）

```make
SRC_DIR := $(shell dirname "$(realpath $(lastword $(MAKEFILE_LIST)))")     # Makefile:123
```
| 点 | 说明 |
|---|---|
| **时机** | **解析期**（Make 读 Makefile 时）就 fork 一个 shell 执行 |
| **返回值** | 命令的 stdout，**换行被压成空格** |
| **代价** | 每次解析都跑 ⇒ **写多了会让 `make` 启动变慢** |
| **`$(MAKEFILE_LIST)`** | Make 内置变量 = 读进来的 Makefile 列表；`$(lastword …)` 取最后一个 |
| **配合 `:=` 用** | 否则（用 `=`）每次引用都重新跑一遍 shell —— 大坑 |

**⇒ 判据：`$(shell …)` 尽量只在解析期算一次（用 `:=`），不要放进 recipe 里反复用。**

---

## 4. `$(if)` / `$(findstring)` / `$(foreach)` —— Make 的"函数式"写法

```make
$(if 条件, 真值, 假值)                      # 条件非空 ⇒ 真值
$(findstring 要找的, 在哪儿找)               # 找到 ⇒ 返回"要找的"；找不到 ⇒ 空
$(foreach 变量, 列表, 对每个元素展开的表达式)
```

**⇒ PX4 的真实用法（[`Makefile:224`](gnu-make-syntax.md#^src-Makefile-224) / `:226`）：**
```make
$(eval VERIFIED_CMAKE_OPTIONS = $(foreach option,$(DESIRED_CMAKE_OPTIONS),$(strip $(findstring $(option)$(space),$(CACHED_CMAKE_OPTIONS)))))
$(eval CMAKE_CACHE_CHECK = $(if $(findstring $(DESIRED_CMAKE_OPTIONS),$(VERIFIED_CMAKE_OPTIONS)),,y))
```
**逐层读：**
```
foreach:  对每个"期望的编译选项"，去"已缓存的选项"里找同名的 → 找到就保留，找不到就是空
findstring: 在拼好的缓存串里找前面那串
if:       找到 ⇒ 真值位是【空】；找不到 ⇒ 返回 'y'
⇒ 结论: CMAKE_CACHE_CHECK 非空 = 缓存不匹配 ⇒ 需要重新 configure
```
**★ 注意 `$(if 条件, 真值, 假值)` 里"真值位是空的"这种写法 —— **故意的**，意思是"匹配就什么都不做"。**

---

## 5. 变量赋值：四种写法的区别（★ 最常踩）

| 写法 | 名字 | 右边什么时候算 | 例子 |
|---|---|---|---|
| `X := v` | **立即展开** | **当场**算完再存 | `SRC_DIR := $(shell dirname …)`（也就跑一次 shell） |
| `X = v` | **递归展开** | **每次用到时**才算 | `A = $(B)` ⇒ B 后来变了，A 跟着变 |
| `X ?= v` | **条件赋值** | 仅在 **X 尚未定义**时赋值 | `CMAKE_ARGS ?=`（[`Makefile:132`](gnu-make-syntax.md#^src-Makefile-132)） |
| `X += v` | **追加** | 在原有值后面接一段 | `CMAKE_ARGS += -DCONFIG=…`（[`Makefile:183`](gnu-make-syntax.md#^src-Makefile-183)） |

**⇒ 一句话判据：**要"一次算好、后面不变" 用 `:=`；要"跟着别的变量走" 用 `=`。**
**⇒ 大坑：`X = $(shell …)` 会让**每次引用**都跑一次 shell —— 该写 `:=`。**

---

## 6. `override` —— 为什么 [`Makefile:183`](gnu-make-syntax.md#^src-Makefile-183) 非写它不可

```make
make rm2027_fmu-h743_default CMAKE_ARGS=-DFOO=1     # 命令行传的变量
```
| 规则 | 说明 |
|---|---|
| **命令行变量优先** | Make **默认**让命令行传的变量**压过** Makefile 里的赋值 |
| **`override` 反过来** | 加了 `override`，这次赋值**始终生效**，命令行压不动 |
| **PX4 为什么要** | `:183` 必须保证 `-DCONFIG=<板名>` 一定进 `CMAKE_ARGS` —— 被用户的 `CMAKE_ARGS=…` 顶掉就麻烦大了 |

---

## 7. 自动变量与 `$$` 转义

| 写法 | 含义 | 出现在 |
|---|---|---|
| `$@` | 当前**目标名** | [`Makefile:245`](gnu-make-syntax.md#^src-Makefile-245) `$(call cmake-build,$@$(BUILD_DIR_SUFFIX))` |
| `$<` | **第一个**依赖 | （本 Makefile 少用） |
| `$^` | **全部**依赖（去重） | （本 Makefile 少用） |
| `$*` | 模式规则里 `%` 匹配到的那部分 | （本 Makefile 少用） |
| `$$x` | **转义**：Make 展开成字面 `$x`，**留给 shell** | recipe 里的 `$$prev`、`$$stamp` |

**⇒ 记法：**`$` 一个给 Make，`$$` 一个给 shell。**
**⇒ 所以 recipe 里要写 shell 变量，必须 `$$var`；直接写 `$var` 会被 Make 当成 Make 变量（多半是空）。**

---

## 8. 全篇最小自验（复制就能跑）

```bash
cat > /tmp/t.mk <<'EOF'
SUF := _replay
ONE := rm2027_fmu-h743_default$(SUF)
$(eval FOO += -DCONFIG=$(patsubst %$(SUF),%,$(ONE)))
$(info [patsubst] $(patsubst %$(SUF),%,$(ONE)))
$(info [eval 之后] FOO=$(FOO))
$(info [if/findstring] $(if $(findstring abc,xxabcxx),找到了,没找到))
$(info [foreach] $(foreach x,a b c,[$(x)]))
define m
$(info [call 收到] $(1))
endef
$(call m,XYZ)
EOF
make -f /tmp/t.mk
```
**实测输出（我真跑过）：**
```
[patsubst] rm2027_fmu-h743_default
[eval 之后] FOO=-DCONFIG=rm2027_fmu-h743_default
[if/findstring] 找到了
[foreach] [a] [b] [c]
[call 收到] XYZ
```
**（末尾 `make: *** 无目标。停止。` 属正常 —— 这里只有 `$(info)`，没写 target。）**

---

## 9. 跳转

- **02 层用它的地方** → [`../../02_code_twin/build/Makefile`](../../02_code_twin/build/Makefile.md)
  （那里讲"`Makefile:237/244/248/179` 各行在干什么"，语法不懂时**回到本篇**）
- **构建流程全景（变量怎么展开成固件）** → [`../../03_moc/00-build-walkthrough`](../../03_moc/00-build-walkthrough.md)
- **其它 01 层提炼知识** → [`../cmake/`](../cmake/)、[`../nuttx/`](../nuttx/)、[`../stm32/`](../stm32/)

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `Makefile`
<a id="src-Makefile-132"></a>
**↓ 文档在讲这里：**[`Makefile:132`](gnu-make-syntax.md#^src-Makefile-132)

```c
   129 │ 	BUILD_DIR_SUFFIX :=
   130 │ endif
   131 │ 
▶  132 │ CMAKE_ARGS ?=
   133 │ 
   134 │ # additional config parameters passed to cmake
   135 │ ifdef EXTERNAL_MODULES_LOCATION
```
> **说明**：X = v | 递归展开 | 每次用到时才算 | A = $(B) ⇒ B 后来变了，A 跟着变 | ┃ X ?= v | 条件赋值 | 仅在 X 尚未定义时赋值 | CMAKE_ARGS ?=（Makefile:132） |
^src-Makefile-132

<a id="src-Makefile-179"></a>
**↓ 文档在讲这里：**[`Makefile:179`](gnu-make-syntax.md#^src-Makefile-179)

```c
   176 │ # Functions
   177 │ # --------------------------------------------------------------------
   178 │ # describe how to build a cmake config
▶  179 │ define cmake-build
   180 │ 	# Strip BUILD_DIR_SUFFIX (e.g. _replay, _failsafe_web) from CONFIG so the
   181 │ 	# board lookup in cmake/px4_config.cmake sees the bare <vendor>_<model>_<label>
   182 │ 	# even when the build dir is suffixed for variant builds.
```
> **说明**：⇒ PX4 里的例子：Makefile:179 的 define cmake-build、Makefile:217 的 define cmake-cache-check。
^src-Makefile-179

<a id="src-Makefile-183"></a>
**↓ 文档在讲这里：**[`Makefile:183`](gnu-make-syntax.md#^src-Makefile-183)

```c
   180 │ 	# Strip BUILD_DIR_SUFFIX (e.g. _replay, _failsafe_web) from CONFIG so the
   181 │ 	# board lookup in cmake/px4_config.cmake sees the bare <vendor>_<model>_<label>
   182 │ 	# even when the build dir is suffixed for variant builds.
▶  183 │ 	$(eval override CMAKE_ARGS += -DCONFIG=$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1)))
   184 │ 	@$(eval BUILD_DIR = "$(SRC_DIR)/build/$(1)")
   185 │ 	@# check if the desired cmake configuration matches the cache then CMAKE_CACHE_CHECK stays empty
   186 │ 	@$(call cmake-cache-check)
```
> **说明**：X ?= v | 条件赋值 | 仅在 X 尚未定义时赋值 | CMAKE_ARGS ?=（Makefile:132） | ┃ X += v | 追加 | 在原有值后面接一段 | CMAKE_ARGS += -DCONFIG=…（Makefile:183） |
> **说明**：6. override —— 为什么 Makefile:183 非写它不可
^src-Makefile-183

<a id="src-Makefile-217"></a>
**↓ 文档在讲这里：**[`Makefile:217`](gnu-make-syntax.md#^src-Makefile-217)

```c
   214 │ endef
   215 │ 
   216 │ # check if the options we want to build with in CMAKE_ARGS match the ones which are already configured in the cache inside BUILD_DIR
▶  217 │ define cmake-cache-check
   218 │ 	@# change to build folder which fails if it doesn't exist and CACHED_CMAKE_OPTIONS stays empty
   219 │ 	@# fetch all previously configured and cached options from the build folder and transform them into the OPTION=VALUE format without type (e.g. :BOOL)
   220 │ 	@$(eval CACHED_CMAKE_OPTIONS = $(shell cd $(BUILD_DIR) 2>/dev/null && cmake -L 2>/dev/null | sed -n 's|\([^[:blank:]]*\):[^[:blank:]]*\(=[^[:blank:]]*\)|\1\2|gp' ))
```
> **说明**：⇒ PX4 里的例子：Makefile:179 的 define cmake-build、Makefile:217 的 define cmake-cache-check。
^src-Makefile-217

<a id="src-Makefile-224"></a>
**↓ 文档在讲这里：**[`Makefile:224`](gnu-make-syntax.md#^src-Makefile-224)

```c
   221 │ 	@# transform the options in CMAKE_ARGS into the OPTION=VALUE format without -D
   222 │ 	@$(eval DESIRED_CMAKE_OPTIONS = $(shell echo $(CMAKE_ARGS) | sed -n 's|-D\([^[:blank:]]*=[^[:blank:]]*\)|\1|gp' ))
   223 │ 	@# find each currently desired option in the already cached ones making sure the complete configured string value is the same
▶  224 │ 	@$(eval VERIFIED_CMAKE_OPTIONS = $(foreach option,$(DESIRED_CMAKE_OPTIONS),$(strip $(findstring $(option)$(space),$(CACHED_CMAKE_OPTIONS)))))
   225 │ 	@# if the complete list of desired options is found in the list of verified options we don't need to reconfigure and CMAKE_CACHE_CHECK stays empty
   226 │ 	@$(eval CMAKE_CACHE_CHECK = $(if $(findstring $(DESIRED_CMAKE_OPTIONS),$(VERIFIED_CMAKE_OPTIONS)),,y))
   227 │ endef
```
> **说明**：⇒ PX4 的真实用法（Makefile:224 / :226）：
^src-Makefile-224

<a id="src-Makefile-245"></a>
**↓ 文档在讲这里：**[`Makefile:245`](gnu-make-syntax.md#^src-Makefile-245)

```c
   242 │ 
   243 │ # All targets.
   244 │ $(ALL_CONFIG_TARGETS):
▶  245 │ 	@$(call cmake-build,$@$(BUILD_DIR_SUFFIX))
   246 │ 
   247 │ # Filter for only default targets to allow omiting the "_default" postfix
   248 │ CONFIG_TARGETS_DEFAULT := $(patsubst %_default,%,$(filter %_default,$(ALL_CONFIG_TARGETS)))
```
> **说明**：⇒ PX4 里的例子：Makefile:179 的 define cmake-build、Makefile:217 的 define cmake-cache-check。 ┃ ⇒ 它们的 $(1) 由 Makefile:245 / :250 的 $(call cmake-build, 目标名) 传进来。
> **说明**：$@ | 当前目标名 | Makefile:245 $(call cmake-build,$@$(BUILD_DIR_SUFFIX)) |
^src-Makefile-245
