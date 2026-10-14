# firmware · 飞控固件

> 建立日期：2026-09-28

## 这里放什么

```text
这里 = 飞控板的「人」的部分
  ├── 开发日志（为什么这么写、依据是什么、什么时候回退过）
  ├── 资源/引脚映射（从原理图提取的硬事实）
  └── 移植计划与状态

PX4 源码里 = 飞控板的「机器」的部分
  └── ~/桌面/RM2027/PX4-Autopilot/boards/rm2027/fmu-h743/
```

## 为什么分成两边

PX4 的板级支持**必须**放在 PX4 源码树的 `boards/<vendor>/<board>/` 下，
否则 CMake / Kconfig 找不到它。所以：

```text
代码 → PX4-Autopilot 仓库（独立 git 仓库，分支 board/fmu-h743）
日志 → 本仓库（rm2027-drone）
```

这么分的好处：日志可以被检索、被 review、被回看；
代码保持 PX4 的目录约定不被污染。

## git 仓库在哪

| 仓库 | 路径 | 远端 |
|---|---|---|
| 笔记/日志（本仓库） | `/mnt/h/AI/shared/projects/competition/rm2027-drone` | gitee `AdoreElysia/by_agent` |
| PX4 源码 | `/home/xien/桌面/RM2027/PX4-Autopilot` | 上游 PX4-Autopilot（本地分支 `board/fmu-h743`） |

查看方式：

```bash
cd /mnt/h/AI/shared/projects/competition/rm2027-drone
git log --oneline          # 看提交历史
git show <hash>            # 看某次提交改了什么
git log -p -- firmware/    # 只看固件相关改动
```

> ⚠️ 注意：`/mnt/h/AI/shared`（工作区根）**不是** git 仓库，只有本项目目录是。

## 当前状态

见 `fmu-h743/README.md`。
