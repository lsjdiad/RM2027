# 工作队列（`platforms/common/px4_work_queue/`）

> **层**：`02_code_twin/`（代码孪生）
>
> | 想看什么 | 去哪 |
> |---|---|
> | 工作队列机制与 `wq_configurations` 全集 | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) §7 |
> | 模块地图 | [`03_moc/03-module-map`](../../03_moc/03-module-map.md) |

---

## 标注源码### `platforms/common/px4_work_queue/WorkQueueManager.cpp`
<a id="src-platforms-common-px4-work-queue-WorkQueueManager-cpp-163"></a>
**↓ 文档在讲这里：**[`platforms/common/px4_work_queue/WorkQueueManager.cpp:163`](work-queue.md#^src-platforms-common-px4-work-queue-WorkQueueManager-cpp-163)

```c
   160 │ 		switch (bus) {
   161 │ 		case 0: return wq_configurations::SPI0;
   162 │ 
▶  163 │ 		case 1: return wq_configurations::SPI1;
   164 │ 
   165 │ 		case 2: return wq_configurations::SPI2;
   166 │ 
```
> **说明**：wq:rate_ctrl | 0（最高） | 3150 | ★ 控制链本体：VehicleAngularVelocity（VehicleAngularVelocity.cpp:47）、mc_rate_control（MulticopterRateControl.cpp:50）、control_allocator（ControlAllocator.cpp:57） | ┃ wq:SPI1 | -2 | 2392 | hxy42688p（WorkQueueManager.cpp:163） |
^src-platforms-common-px4-work-queue-WorkQueueManager-cpp-163
