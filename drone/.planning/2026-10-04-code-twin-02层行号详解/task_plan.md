# task_plan：code-twin 的 02 层「行号详解」

## 目标（用户原话）
> 「我向直接跳转到 02 层，并在这里面详细讲解有关行号」

**⇒ 03_moc 只负责讲"流程 / 为什么"，行号级的详细讲解【下沉到 02 层】，
   03_moc 用链接跳过去；读者不用在 MOC 和附录之间来回找。**

## 问题现状
- **03_moc 里堆了大量行号级细节**（如 00-build-walkthrough 里 `Makefile:237/244/248` 逐行讲解）
  ⇒ 与"02 层是代码孪生"的分工重叠
- **02 层缺 build 相关的孪生篇**：`Makefile` / 根 `CMakeLists.txt` 的逐行详解没有落点
  （现有 02 层只覆盖 bootloader / board / modules / drivers / params）

## 步骤
- [ ] 1. 建 `02_code_twin/build/Makefile.md` —— Makefile 的行号详解（用户举的例子在这）
- [ ] 2. 建 `02_code_twin/build/CMakeLists.md` —— 根 CMakeLists 的行号详解
- [ ] 3. `03_moc/00-build-walkthrough.md` 里那几段行号详解 → 改为"跳转到 02 层对应篇"
- [ ] 4. 在 03_moc 每篇顶部加一句分工说明（MOC 讲流程 / 02 讲行号）
- [ ] 5. 验证：链接可达、无重复、正文未损
- [ ] 6. 提交

## 验收
- 从 `03_moc/00-build-walkthrough.md` 点一次就能跳到 `Makefile:237` 的行号详解
- 行号详解里每一行都有：「代码原文 + 这一行在干什么 + 为什么关键」
- 不破坏已有的 1969 条源码跳转链接与 972 处标注
