# PX4 里的 C 宏与属性（提炼知识）

> **这是 01 层（提炼知识）** —— 从 PX4 源码里萃取的 **C 预处理 + `__attribute__`** 那套"魔法"。
> **02 层遇到它们时链接回这里**；02 层只讲"某个文件的行号在干什么"。
>
> **什么时候读这篇**：看到 `__EXPORT` / `__attribute__((…))` / `#x` / `x##y` / `__PACKED` /
> `__BEGIN_DECLS` 而**只"大概知道"、不敢确定**的时候。
> **出处**：源码根见 [`../../tools/source-root.conf`](../../tools/source-root.conf)。

---

## 0. 讲什么 / 不讲什么

| 讲 | 不讲 |
|---|---|
| **`__EXPORT` / `__PRIVATE`** —— 你在生成的话题头里就会撞到 | 动态库/ELF 符号解析的完整原理 |
| **`__BEGIN_DECLS` / `__END_DECLS`** —— C++ 里包 C 头 | `extern "C"` 的名字修饰规则细节（知道目的即可） |
| **`__attribute__` 最常撞的 6 种** | GCC 全部 attribute（几百个） |
| **★ `#` 字符串化 与 `##` 记号拼接** —— 配 PX4 的真实实例 | 预处理器标准条文 |
| **`##__VA_ARGS__` 的 GNU 扩展**（逗号吞噬） | 其它编译器的方言 |
| `PX4_ISFINITE` / `OK` / `ERROR` 这类小宏 | 把 PX4 所有宏列一遍 |

**★ 为什么值得单独一篇：**这些宏**没有教程会讲**，但**读 PX4 源码时到处是** ——
不认识就只能"猜它是什么意思"，而它们往往决定了**编译期行为**（导出符号 / 内存布局 / 优化）。

---

## 1. `__EXPORT` / `__PRIVATE` —— 符号可见性

**定义在 `src/include/visibility.h`（`:47` / `:52`）：**
```c
#define __EXPORT   __attribute__ ((visibility ("default")))
#define __PRIVATE  __attribute__ ((visibility ("hidden")))
```c

| 宏 | 含义 | 大白话 |
|---|---|---|
| **`__EXPORT`** | 符号**对外可见** | "允许别的编译单元/其它模块找到我" |
| `__PRIVATE` | 符号**隐藏** | "只在本文库内部用" |

**★ 你在哪里会撞到它：**生成的话题头里就有 ——
```c
struct __EXPORT sensor_gyro_s {      // build/.../uORB/topics/sensor_gyro.h
```
```c
extern "C" const struct orb_metadata __orb_##_name __EXPORT   // ORB_DECLARE
```

**⇒ 关键认知：`__EXPORT` 在这里**不改变结构体的语义**，只是告诉链接器"别把它藏起来"。**
**⇒ 所以看到它**不需要紧张** —— 99% 的场合它就是"让符号可见"的记号。**

**★ 注意有**两份** `visibility.h`（内容相同）：**
```
src/include/visibility.h                                  ← 主用的（PX4 源码）
platforms/nuttx/src/canbootloader/include/visibility.h    ← CAN bootloader 独立用一份（它不依赖 PX4 源码树）
```

---

## 2. `__BEGIN_DECLS` / `__END_DECLS` —— C++ 里包 C 头

**同样在 `src/include/visibility.h`（`:55-59`）：**
```c
#ifdef __cplusplus
#  define __BEGIN_DECLS   extern "C" {
#  define __END_DECLS     }
#else
#  define __BEGIN_DECLS
#  define __END_DECLS
#endif
```

| 场合 | 展开成 | 效果 |
|---|---|---|
| **C++ 编译** | `extern "C" {` … `}` | 按 C 规则生成符号名（**不做 C++ 名字修饰**） |
| **C 编译** | **空** | 什么都不做 |

**★ 为什么需要：**一个头文件要**同时给 C 和 C++**用，且 C++ 侧要能链接到 C 编译出来的符号。**
**⇒ 判据：看到 `__BEGIN_DECLS` 就知道"这是 **C 接口**，故意不修饰名字"。**

**⚠️ 一个相关的坑（PX4 编译报错时常见）：**
```
error: expected '}'  /  does not name a type  等一堆莫名其妙
⇒ 往往是【该加 __BEGIN_DECLS 的 C 头被 C++ 直接 include 了】
```

---

## 3. `__attribute__` —— 最常撞的 6 种（按本仓出现次数排）

**统计口径**：`platforms/common/include` 与 `src/lib` 里的出现次数。

| 属性 | 次数 | 作用 | 一句话 |
|---|---|---|---|
| **`packed`** | 19 | **不留对齐填充** | 结构体/数组按字节紧排 ⇒ 常用于**协议帧、寄存器映射** |
| **`weak`** | 17 | **弱符号** | 允许被同名强符号覆盖 ⇒ 常用于"默认实现 + 板级可覆盖" |
| **`deprecated`** | 14 | **编译告警** | 用了它会警告 ⇒ 读代码时这是"这条路别走了"的信号 |
| **`used`** | 12 | **强制保留** | 即使看起来没被引用也不许优化掉 ⇒ 常用于中断向量/注册表 |
| **`aligned(n)`** | 11 | **指定对齐** | 如 `aligned(4)`；`aligned(1)` 就等于 packed 的意图 |
| **`always_inline`** | 7 | **必定内联** | 同 `inline` + 强制 ⇒ 常用于**极热的短函数** |
| `noreturn` | 6 | **不返回** | 让编译器省掉返回代码（`panic`/`exit` 类） |
| `noinline` | 6 | **不许内联** | 常用于**放到 RAM 里执行的 flash 操作**（这类必须不内联） |

**★ 三个你会真的用到的：**
```c
__attribute__((packed))            // 协议/寄存器结构 —— 但【性能有代价】（非对齐访问）
__attribute__((weak))              // 写一个"默认实现"，让板级或测试可以覆盖
__attribute__((noinline))          // flash 编程/擦除期间执行的函数必须放 RAM 且不内联
```

**⇒ CMSIS 把它包装成了更好记的名字（[`cmsis_gcc.h:62`](px4-c-macros.md#^src-src-modules-gyro-fft-CMSIS-5-CMSIS-Core-Include-cmsis-gcc-h-62)）：**
```c
#define __PACKED          __attribute__((packed, aligned(1)))
#define __PACKED_STRUCT   struct __attribute__((packed, aligned(1)))
#define __PACKED_UNION    union  __attribute__((packed, aligned(1)))
```
**⇒ 所以源码里看到 `__PACKED_STRUCT foo { … };` = "紧凑排布的结构体"。**

---

## 4. ★★ `#` 字符串化 与 `##` 记号拼接（本篇最该记的一条）

**这两条是 C 预处理器里唯一的"元编程"手段。**

### 4.1 `#x` —— **字符串化**：把宏参数变成字符串字面量

```c
#define STR(x)   #x
STR(hello)        // → "hello"
STR(1 + 2)        // → "1 + 2"    ← ★ 不做算术！只是把源码文本抓成字符串
```
**★ PX4 真实实例（我们已经见过的）：**
```c
#define ORB_DEFINE(_name, ...) \
	const struct orb_metadata __orb_##_name = {  \
		#_name,                                   \    // ← ★ "sensor_gyro" 这个字符串就是这么来的
		...
```
**⇒ 所以话题名 `"sensor_gyro"` **不是手写的**，是 `#_name` 从宏参数抓出来的。**

### 4.2 `x##y` —— **记号拼接**：把两段拼成一个标识符

```c
#define CONCAT(a, b)   a##b
CONCAT(my, Func)      // → myFunc        ← ★ 拼出一个新标识符（变量名/函数名/宏名都行）
```

**★ PX4 真实实例（三个，从简到繁）：**

**① 最简单的（[`platforms/common/uORB/uORB.h:80`](px4-c-macros.md#^src-platforms-common-uORB-uORB-h-80) / `:88` / `:110`）—— 我们已经讲过：**
```c
#define ORB_ID(_name)         &__orb_##_name                    // sensor_gyro → __orb_sensor_gyro
#define ORB_DECLARE(_name)    extern … const struct orb_metadata __orb_##_name __EXPORT
```

**② 教科书级（[`platforms/common/include/px4_platform_common/board_common.h:808`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-board-common-h-808)）：**
```c
#define PX4_MFT_HW_SUPPORTED(ID)         PX4_MFT_HW_SUPPORTED_##ID
// 用法：PX4_MFT_HW_SUPPORTED(IMU)  →  PX4_MFT_HW_SUPPORTED_IMU
// ⇒ 于是"板级能力表"可以按 ID 自动生成一堆宏名，不用手写几十条
```
（[`board_common.h:809`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-board-common-h-809) 是同一套：`REQUIRED` / `IS_ONBOARD` / `IS_OFFBOARD` / `IS_CONNECTION_KNOWN`）

**③ 拼出一个宏名再调用它（[`platforms/common/include/px4_platform_common/param_macros.h:197`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-param-macros-h-197) / `:229`）：**
```c
#define APPLY_ALL_H3(t, n, ...)   APPLY##n(t, __VA_ARGS__)
// n=3 时 → APPLY3(t, ...)  ← ★ 先拼出宏名，再让预处理器去展开那个宏
// ⇒ 这是"按参数个数分派到不同宏"的标准手法（PX4 用它批量展开参数）
```

### 4.3 ⚠️ 一个必须知道的细节：**拼接/字符串化的参数不会先展开**

```c
#define STR(x)      #x
#define XSTR(x)     STR(x)      // ★ 多套一层
#define VERSION     2
STR(VERSION)     // → "VERSION"     ← 不会展开成 "2"
XSTR(VERSION)    // → "2"           ← 套一层才会先展开再字符串化
```
**⇒ 规则：**`#` 和 `##` 的操作数**保持原样**（不展开）。想先展开，就再套一层宏。****

---

## 5. `##__VA_ARGS__` —— GNU 扩展（"逗号吞噬"）

**[`platforms/common/include/px4_platform_common/param_macros.h:195`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-param-macros-h-195)：**
```c
#define NUM_ARGS(...)  NUM_ARGS_H1(dummy, ##__VA_ARGS__, 149, 148, …, 1, 0)
```

| 写法 | 效果 |
|---|---|
| `__VA_ARGS__` | 标准写法：把可变参数原样放进来 |
| **`##__VA_ARGS__`** | ★ **GNU 扩展**：如果可变参数**为空**，就把前面那个逗号**一起吃掉** |

**⇒ 为什么需要它：**
```c
#define LOG(fmt, ...)  printf(fmt, ##__VA_ARGS__)
LOG("hi")            // 若用 ## ⇒ printf("hi")        ✓
                     // 不用 ## ⇒ printf("hi", )     ✗ 语法错误
```
**⇒ 所以 `NUM_ARGS` 那串是在**数参数个数**（把参数顶到一串数字前面，看落在哪个数字上）——**
**`##` 是为了让"零参数"这种情况也能编译过。**

**⚠️ 它**不是标准 C**（GCC/Clang 支持，`-pedantic` 会告警）—— 读 PX4 源码时认得就行，自己写要谨慎。**

---

## 6. 几个高频小宏（读代码时省事）

**`platforms/common/include/px4_platform_common/defines.h`：**
| 宏 | 行号 | 展开/含义 |
|---|---|---|
| `PX4_ISFINITE(x)` | `:58` | `__builtin_isfinite(x)` ← **编译器内建**，比 `isfinite()` 快 |
| `OK` | `:111` | `0` |
| `ERROR` | `:112` | `-1` |
| `MAX_RAND` | `:113` | `32767` |

**常用但定义在别处的：**
| 宏 | 在哪 | 备注 |
|---|---|---|
| `ARRAY_SIZE(a)` | 标准写法是 `sizeof(a)/sizeof(a[0])` | PX4 里也有自己的定义 |
| `MIN(a,b)` / `MAX(a,b)` | 各处 | **⚠️ 宏的经典坑：`MIN(i++, j)` 会自增两次** |
| `CONSTRAINED(v, lo, hi)` | PX4 常见 | 夹取到区间 |
| `PX4_ISFINITE` | [`defines.h:58`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-defines-h-58) | 判断浮点合法性（**不许用 `x == x` 那种写法**） |

**⇒ 判据：读 PX4 时遇到不认识的宏，**先看它是"值"还是"语法糖"** ——**
**`PX4_ISFINITE` 是值级，`__EXPORT` 是语法糖（不影响语义），`#`/`##` 是元编程。**

---

## 7. 自己验证（30 秒，只跑预处理器，不编译）

```bash
cat > /tmp/m.c <<'EOF'
#include <stdio.h>
#define STR(x)    #x
#define XSTR(x)   STR(x)
#define CAT(a,b)  a##b
#define VERSION   2
STR(VERSION)                /* 期望: "VERSION" —— 不展开 */
XSTR(VERSION)               /* 期望: "2"       —— 套一层才展开 */
CAT(my, Func)               /* 期望: myFunc    —— 拼出新标识符 */
struct __attribute__((packed)) S { char a; int b; };   /* 期望: 5 字节，不是 8 */
EOF
gcc -E /tmp/m.c 2>/dev/null | grep -E '"VERSION"|"2"|myFunc'
echo '--- 结构体大小 ---'
cat > /tmp/s.c <<'EOF'
#include <stdio.h>
struct __attribute__((packed)) S { char a; int b; };
struct N { char a; int b; };
int main(void){ printf("packed=%zu  普通=%zu\n", sizeof(struct S), sizeof(struct N)); }
EOF
gcc /tmp/s.c -o /tmp/s && /tmp/s
```
**实测输出：**
```
"VERSION"
"2"
myFunc
packed=5  普通=8          ← ★ packed 真的省了 3 字节对齐填充
```
**⇒ 亲手跑一遍，§4 就再也不会忘。**

---

## 8. 跳转

- **02 层遇到它们的地方** → [`../../02_code_twin/`](../../02_code_twin/)（尤其 `bootloader/` 与 `board/`）
- **uORB 里 `__EXPORT` / `#_name` / `##` 的完整用法** → [`../uorb/uorb-mechanism`](../uorb/uorb-mechanism.md) §3
- **启动汇编与 C 运行时初始化**（`Reset_Handler` / `__libc_init_array`）→ [`../stm32/startup-and-crt`](../stm32/startup-and-crt.md)（待写）
- **其它 01 层** → [`../cmake/cmake-syntax`](../cmake/cmake-syntax.md)、[`../make/gnu-make-syntax`](../make/gnu-make-syntax.md)、[`../nuttx/`](../nuttx/)

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `platforms/common/include/px4_platform_common/board_common.h`
<a id="src-platforms-common-include-px4-platform-common-board-common-h-808"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/board_common.h:808`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-board-common-h-808)

```c
   805 │ #  define PX4_MFT_HW_IS_CONNECTION_KNOWN(ID) (board_query_manifest((ID))->connection != px4_hw_con_unknown)
   806 │ #elif defined(BOARD_HAS_STATIC_MANIFEST) && BOARD_HAS_STATIC_MANIFEST == 1
   807 │ /* Board has a static configuration and will supply what it has */
▶  808 │ #  define PX4_MFT_HW_SUPPORTED(ID)           PX4_MFT_HW_SUPPORTED_##ID
   809 │ #  define PX4_MFT_HW_REQUIRED(ID)            PX4_MFT_HW_REQUIRED_##ID
   810 │ #  define PX4_MFT_HW_IS_ONBOARD(ID)          PX4_MFT_HW_IS_ONBOARD_##ID
   811 │ #  define PX4_MFT_HW_IS_OFFBOARD(ID)         PX4_MFT_HW_IS_OFFBOARD_##ID
```
> **说明**：② 教科书级（platforms/common/include/px4_platform_common/board_common.h:808）：
^src-platforms-common-include-px4-platform-common-board-common-h-808

<a id="src-platforms-common-include-px4-platform-common-board-common-h-809"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/board_common.h:809`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-board-common-h-809)

```c
   806 │ #elif defined(BOARD_HAS_STATIC_MANIFEST) && BOARD_HAS_STATIC_MANIFEST == 1
   807 │ /* Board has a static configuration and will supply what it has */
   808 │ #  define PX4_MFT_HW_SUPPORTED(ID)           PX4_MFT_HW_SUPPORTED_##ID
▶  809 │ #  define PX4_MFT_HW_REQUIRED(ID)            PX4_MFT_HW_REQUIRED_##ID
   810 │ #  define PX4_MFT_HW_IS_ONBOARD(ID)          PX4_MFT_HW_IS_ONBOARD_##ID
   811 │ #  define PX4_MFT_HW_IS_OFFBOARD(ID)         PX4_MFT_HW_IS_OFFBOARD_##ID
   812 │ #  define PX4_MFT_HW_IS_CONNECTION_KNOWN(ID) PX4_MFT_HW_IS_CONNECTION_KNOWN_##ID
```
> **说明**：（board_common.h:809 是同一套：REQUIRED / IS_ONBOARD / IS_OFFBOARD / IS_CONNECTION_KNOWN）
^src-platforms-common-include-px4-platform-common-board-common-h-809

### `platforms/common/include/px4_platform_common/defines.h`
<a id="src-platforms-common-include-px4-platform-common-defines-h-58"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/defines.h:58`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-defines-h-58)

```c
    55 │ static inline constexpr bool PX4_ISFINITE(float x) { return __builtin_isfinite(x); }
    56 │ static inline constexpr bool PX4_ISFINITE(double x) { return __builtin_isfinite(x); }
    57 │ #else
▶   58 │ #define PX4_ISFINITE(x) __builtin_isfinite(x)
    59 │ #endif /* __cplusplus */
    60 │ 
    61 │ #if defined(__PX4_NUTTX)
```
> **说明**：CONSTRAINED(v, lo, hi) | PX4 常见 | 夹取到区间 | ┃ PX4_ISFINITE | defines.h:58 | 判断浮点合法性（不许用 x == x 那种写法） |
^src-platforms-common-include-px4-platform-common-defines-h-58

### `platforms/common/include/px4_platform_common/param_macros.h`
<a id="src-platforms-common-include-px4-platform-common-param-macros-h-195"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/param_macros.h:195`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-param-macros-h-195)

```c
   192 │ #define APPLY149(t, aaa, aab, aac, aad, aae, aaf, aag, aah, aai, aaj, aak, aal, aam, aan, aao, aap, aaq, aar, aas, aat, aau, aav, aaw, aax, aay, aaz, aba, abb, abc, abd, abe, abf, abg, abh, abi, abj, abk, abl, abm, abn, abo, abp, abq, abr, abs, abt, abu, abv, abw, abx, aby, abz, aca, acb, acc, acd, ace, acf, acg, ach, aci, acj, ack, acl, acm, acn, aco, acp, acq, acr, acs, act, acu, acv, acw, acx, acy, acz, ada, adb, adc, add, ade, adf, adg, adh, adi, adj, adk, adl, adm, adn, ado, adp, adq, adr, ads, adt, adu, adv, adw, adx, ady, adz, aea, aeb, aec, aed, aee, aef, aeg, aeh, aei, aej, aek, ael, aem, aen, aeo, aep, aeq, aer, aes, aet, aeu, aev, aew, aex, aey, aez, afa, afb, afc, afd, afe, aff, afg, afh, afi, afj, afk, afl, afm, afn, afo, afp, afq, afr, afs) t(aaa) t(aab) t(aac) t(aad) t(aae) t(aaf) t(aag) t(aah) t(aai) t(aaj) t(aak) t(aal) t(aam) t(aan) t(aao) t(aap) t(aaq) t(aar) t(aas) t(aat) t(aau) t(aav) t(aaw) t(aax) t(aay) t(aaz) t(aba) t(abb) t(abc) t(abd) t(abe) t(abf) t(abg) t(abh) t(abi) t(abj) t(abk) t(abl) t(abm) t(abn) t(abo) t(abp) t(abq) t(abr) t(abs) t(abt) t(abu) t(abv) t(abw) t(abx) t(aby) t(abz) t(aca) t(acb) t(acc) t(acd) t(ace) t(acf) t(acg) t(ach) t(aci) t(acj) t(ack) t(acl) t(acm) t(acn) t(aco) t(acp) t(acq) t(acr) t(acs) t(act) t(acu) t(acv) t(acw) t(acx) t(acy) t(acz) t(ada) t(adb) t(adc) t(add) t(ade) t(adf) t(adg) t(adh) t(adi) t(adj) t(adk) t(adl) t(adm) t(adn) t(ado) t(adp) t(adq) t(adr) t(ads) t(adt) t(adu) t(adv) t(adw) t(adx) t(ady) t(adz) t(aea) t(aeb) t(aec) t(aed) t(aee) t(aef) t(aeg) t(aeh) t(aei) t(aej) t(aek) t(ael) t(aem) t(aen) t(aeo) t(aep) t(aeq) t(aer) t(aes) t(aet) t(aeu) t(aev) t(aew) t(aex) t(aey) t(aez) t(afa) t(afb) t(afc) t(afd) t(afe) t(aff) t(afg) t(afh) t(afi) t(afj) t(afk) t(afl) t(afm) t(afn) t(afo) t(afp) t(afq) t(afr) t(afs)
   193 │ 
   194 │ #define NUM_ARGS_H1(dummy, x149, x148, x147, x146, x145, x144, x143, x142, x141, x140, x139, x138, x137, x136, x135, x134, x133, x132, x131, x130, x129, x128, x127, x126, x125, x124, x123, x122, x121, x120, x119, x118, x117, x116, x115, x114, x113, x112, x111, x110, x109, x108, x107, x106, x105, x104, x103, x102, x101, x100, x99, x98, x97, x96, x95, x94, x93, x92, x91, x90, x89, x88, x87, x86, x85, x84, x83, x82, x81, x80, x79, x78, x77, x76, x75, x74, x73, x72, x71, x70, x69, x68, x67, x66, x65, x64, x63, x62, x61, x60, x59, x58, x57, x56, x55, x54, x53, x52, x51, x50, x49, x48, x47, x46, x45, x44, x43, x42, x41, x40, x39, x38, x37, x36, x35, x34, x33, x32, x31, x30, x29, x28, x27, x26, x25, x24, x23, x22, x21, x20, x19, x18, x17, x16, x15, x14, x13, x12, x11, x10, x9, x8, x7, x6, x5, x4, x3, x2, x1, x0, ...) x0
▶  195 │ #define NUM_ARGS(...) NUM_ARGS_H1(dummy, ##__VA_ARGS__, 149, 148, 147, 146, 145, 144, 143, 142, 141, 140, 139, 138, 137, 136, 135, 134, 133, 132, 131, 130, 129, 128, 127, 126, 125, 124, 123, 122, 121, 120, 119, 118, 117, 116, 115, 114, 113, 112, 111, 110, 109, 108, 107, 106, 105, 104, 103, 102, 101, 100, 99, 98, 97, 96, 95, 94, 93, 92, 91, 90, 89, 88, 87, 86, 85, 84, 83, 82, 81, 80, 79, 78, 77, 76, 75, 74, 73, 72, 71, 70, 69, 68, 67, 66, 65, 64, 63, 62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
   196 │ 
   197 │ #define APPLY_ALL_H3(t, n, ...) APPLY##n(t, __VA_ARGS__)
   198 │ #define APPLY_ALL_H2(t, n, ...) APPLY_ALL_H3(t, n, __VA_ARGS__)
```
> **说明**：platforms/common/include/px4_platform_common/param_macros.h:195：
^src-platforms-common-include-px4-platform-common-param-macros-h-195

<a id="src-platforms-common-include-px4-platform-common-param-macros-h-197"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/param_macros.h:197`](px4-c-macros.md#^src-platforms-common-include-px4-platform-common-param-macros-h-197)

```c
   194 │ #define NUM_ARGS_H1(dummy, x149, x148, x147, x146, x145, x144, x143, x142, x141, x140, x139, x138, x137, x136, x135, x134, x133, x132, x131, x130, x129, x128, x127, x126, x125, x124, x123, x122, x121, x120, x119, x118, x117, x116, x115, x114, x113, x112, x111, x110, x109, x108, x107, x106, x105, x104, x103, x102, x101, x100, x99, x98, x97, x96, x95, x94, x93, x92, x91, x90, x89, x88, x87, x86, x85, x84, x83, x82, x81, x80, x79, x78, x77, x76, x75, x74, x73, x72, x71, x70, x69, x68, x67, x66, x65, x64, x63, x62, x61, x60, x59, x58, x57, x56, x55, x54, x53, x52, x51, x50, x49, x48, x47, x46, x45, x44, x43, x42, x41, x40, x39, x38, x37, x36, x35, x34, x33, x32, x31, x30, x29, x28, x27, x26, x25, x24, x23, x22, x21, x20, x19, x18, x17, x16, x15, x14, x13, x12, x11, x10, x9, x8, x7, x6, x5, x4, x3, x2, x1, x0, ...) x0
   195 │ #define NUM_ARGS(...) NUM_ARGS_H1(dummy, ##__VA_ARGS__, 149, 148, 147, 146, 145, 144, 143, 142, 141, 140, 139, 138, 137, 136, 135, 134, 133, 132, 131, 130, 129, 128, 127, 126, 125, 124, 123, 122, 121, 120, 119, 118, 117, 116, 115, 114, 113, 112, 111, 110, 109, 108, 107, 106, 105, 104, 103, 102, 101, 100, 99, 98, 97, 96, 95, 94, 93, 92, 91, 90, 89, 88, 87, 86, 85, 84, 83, 82, 81, 80, 79, 78, 77, 76, 75, 74, 73, 72, 71, 70, 69, 68, 67, 66, 65, 64, 63, 62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49, 48, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)
   196 │ 
▶  197 │ #define APPLY_ALL_H3(t, n, ...) APPLY##n(t, __VA_ARGS__)
   198 │ #define APPLY_ALL_H2(t, n, ...) APPLY_ALL_H3(t, n, __VA_ARGS__)
   199 │ #define APPLY_ALL(t, ...) APPLY_ALL_H2(t, NUM_ARGS(__VA_ARGS__), __VA_ARGS__)
   200 │ 
```
> **说明**：③ 拼出一个宏名再调用它（platforms/common/include/px4_platform_common/param_macros.h:197 / :229）：
^src-platforms-common-include-px4-platform-common-param-macros-h-197

### `platforms/common/uORB/uORB.h`
<a id="src-platforms-common-uORB-uORB-h-80"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORB.h:80`](px4-c-macros.md#^src-platforms-common-uORB-uORB-h-80)

```c
    77 │  *
    78 │  * @param _name		The name of the topic.
    79 │  */
▶   80 │ #define ORB_ID(_name)		&__orb_##_name
    81 │ 
    82 │ /**
    83 │  * Declare (prototype) the uORB metadata for a topic (used by code generators).
```
> **说明**：① 最简单的（platforms/common/uORB/uORB.h:80 / :88 / :110）—— 我们已经讲过：
^src-platforms-common-uORB-uORB-h-80

### `src/modules/gyro_fft/CMSIS_5/CMSIS/Core/Include/cmsis_gcc.h`
<a id="src-src-modules-gyro-fft-CMSIS-5-CMSIS-Core-Include-cmsis-gcc-h-62"></a>
**↓ 文档在讲这里：**[`src/modules/gyro_fft/CMSIS_5/CMSIS/Core/Include/cmsis_gcc.h:62`](px4-c-macros.md#^src-src-modules-gyro-fft-CMSIS-5-CMSIS-Core-Include-cmsis-gcc-h-62)

```c
    59 │   #define __WEAK                                 __attribute__((weak))
    60 │ #endif
    61 │ #ifndef   __PACKED
▶   62 │   #define __PACKED                               __attribute__((packed, aligned(1)))
    63 │ #endif
    64 │ #ifndef   __PACKED_STRUCT
    65 │   #define __PACKED_STRUCT                        struct __attribute__((packed, aligned(1)))
```
> **说明**：⇒ CMSIS 把它包装成了更好记的名字（cmsis_gcc.h:62）：
^src-src-modules-gyro-fft-CMSIS-5-CMSIS-Core-Include-cmsis-gcc-h-62
