# task_plan：code-twin 语法盲点审计

## 目标（用户原话）
> 「还有别的地方也是，如果遇到我不会的，你及时补充语法知识讲解」
> 「注意用 planning with files 思考」
> 「**哪些我可能不会？哪些还需要更改？**」

**⇒ 交付一份**审计表**：把 43 篇文档里出现的"硬语法"，按【你可能不会的程度】排序，
   并标出【已有讲解 / 缺讲解 / 需要改写法】。**

## 为什么由我判断"你可能不会"
用户背景（本项目已确认的事实）：
- **会写 C / 会用 CubeMX、Keil/IAR 那套**（自己做过 F103 测试固件、AM32 电调改造）
- **PX4 是新的**：uORB / work queue / module 模型 / 板级移植都是这两周才接触
- **刚说看不懂**：GNU Make 的 `$(eval …)` / `$(call …)` / `patsubst`（已补 §6）
- **手上有 Ozone/ST-Link 的调试习惯**，但**不熟 NuttX**
⇒ 所以"可能不会"的判据 = **偏离"裸机 C + CubeMX"经验越远，越需要讲**

## 审计维度（每个语法点按此打分）
| 维度 | 含义 |
|---|---|
| **陌生度** | 与"裸机 C + Keil"经验的距离：低/中/高 |
| **踩到频率** | 读这套文档时多久会遇到一次 |
| **已讲?** | 文档里有没有解释（有→够不够；无→要补） |
| **建议动作** | 补讲解 / 补例子 / 改写法 / 不用管 |

## 步骤
- [ ] 1. 扫描 43 篇的**全部代码块**，抽语言与构造
- [ ] 2. 分类：Make / CMake / Kconfig / 链接脚本 / C 宏 / shell / uORB / 汇编启动 / Python 工具
- [ ] 3. 逐类判"陌生度 × 已讲?"，产出审计表
- [ ] 4. 按「最可能不会 + 最缺讲解」排序，给出**要补的清单**
- [ ] 5. 落盘到 `work/px4-code-twin/04_notes/语法盲点审计.md`
- [ ] 6. 用户挑要补的，我补 §语法节

## 验收
- 每个语法点都有：**在哪出现（file:line / 篇名）**、**陌生度**、**已讲否**、**建议动作**
- 清单按优先级排序（不是平铺）
- **不猜用户水平** —— 判据写出来（"偏离裸机 C 多远"）

---

## ★ 纠偏（用户指出，2026-10-04 追加）

**用户原话**：
> 「你再回头看 rm_note。你这个知识点讲解为什么要放到文件最低下？？
>  不应该来一个专门的比较底层的东西去解决这个问题吗？」

**⇒ 对。RM_note 的 README 写得很明确：**
```
01_extracted/  …… 从原始资料中萃取的结构化知识（CMake 语法、CAN 过滤器、kfifo 原理等）
               ★ 代码孪生层遇到新概念时 链接回这里
02_code_twin/  …… 摘取关键代码片段 + 逐段解析，★ 首次遇到某语法时 链接回 01 层
引用规则：第 N 层只能向下引用第 N-1 层，不可反向
```
**而它的实际 01 层就有** `01_extracted/cmake/cmake-basic-syntax.md`、`01_extracted/algorithm/函数指针.md`**，
02 层引用写成** `[[01_extracted/algorithm/kfifo-design#SPSC 架构]]`**（带锚点）。**

**我犯的错**：把「GNU Make 语法详解」塞进了 `02_code_twin/build/Makefile.md` 的最底下（§6，还排在"跳转"之后）。
**正确做法**：语法/概念属于 01 层，02 层只**链接**过去。

**⇒ 新增步骤（插到原步骤之前）：**
- [ ] 0-A. 建 `01_extracted/make/gnu-make-syntax.md` —— 把 §6 搬过去并**扩充**（它现在是"专职那一篇"）
- [ ] 0-B. `02_code_twin/build/Makefile.md` 的 §6 → 收缩成**一句话摘要 + 链接到 01 层**
- [ ] 0-C. 把审计里其余语法主题也一律规划到 01 层（cmake / c-macros / uorb / asm / kconfig / ld）
- [ ] 0-D. 重跑流水线（链接/标注），验证无重复、正文完好

---

## 追加任务 B′（用户说「来吧」）

- [ ] B′-1. `01_extracted/cmake/cmake-syntax.md` —— **CMake 语法（生成期视角）**
       重点：function() vs macro() 的【作用域差异】★最大坑 / 目录作用域与 PARENT_SCOPE /
             GLOBAL 属性为什么要用 / configure_file vs add_custom_command / if() 的写法怪癖 /
             list() 与 foreach() / CACHE 变量
- [ ] B′-2. `02_code_twin/build/CMakeLists.md` —— 根 `CMakeLists.txt` 的**行号孪生**（只讲"这一行在干什么"）
- [ ] B′-3. 跑流水线（链接/标注），验证：无重复段、链接可达、正文完好
- [ ] B′-4. 提交

---

## 追加任务 A′（用户说「你接着干就行」）

- [ ] A′-1. `01_extracted/uorb/uorb-mechanism.md` —— **uORB / PX4 框架机制**（01 层）
       重点：`.msg` → 生成代码长什么样 / ORB_DECLARE·ORB_DEFINE·ORB_ID 宏 /
             uORB::Subscription vs Publication vs C API / ModuleBase 与 WorkItem 的关系 /
             task_spawn 与 work queue 的区别 / px4::wq_configurations 各队列 /
             ★ 发布/订阅的语义（last-value、无队列、拷贝语义）
- [ ] A′-2. 在相关 02 篇里加"语法/机制不懂→去 01 层"的链接
- [ ] A′-3. 跑流水线 + 验证（行号逐条命中、链接可达、无重复段）
- [ ] A′-4. 提交

---

## 追加：P1 链接改造 + P5 全局变量篇（用户："把这种链接改掉啊啊啊啊"）

- [x] P1 把 file:// 外链改成站内跳转（新增 tools/anchorize-sources.py）
- [x] P5 新增 01_extracted/cmake/px4-global-variables.md（回答"哪些变量又关键又全局"）
- [ ] P2 分层：数据测完发现"搬走 92 个文件"是错方向 ⇒ 改为务实版（03_moc 顶部加定位语 + 补 drivers 下该有的页）
- [x] 流水线定序：link → annotate → anchorize（且 annotate 会冲掉锚点，必须重跑 anchorize）
