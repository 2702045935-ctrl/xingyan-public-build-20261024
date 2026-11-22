# 10,000 人群启动闪退

- 日期：2026-11-22
- 设备：iPhone18,4 / iOS 27.0.1
- UDID：00008150-00191CC40C42401C
- 构建：2611220956
- 提交：4f2ef47
- 压力配置：`XINGYAN_STRESS_PROFILE=group-300000-members-10000`
- 自动打开：`XINGYAN_STRESS_AUTO_OPEN=1`

## 异常

崩溃报告：`/CHRIS-2026-11-22-110307.ips`

```text
Exception: EXC_CRASH
Application Specific Information: abort() called
```

关键栈：

```text
-[UICollectionView _updateRowsAtIndexPaths:updateAction:updates:]
-[UICollectionView reloadItemsAtIndexPaths:]
-[UICollectionViewAccessibility reloadItemsAtIndexPaths:]
NativeStaticList.Coordinator.refreshAfterForeground()
```

## 初步定位

`NativeStaticList` 在前台恢复时直接使用
`collection.indexPathsForVisibleItems` 调用 `reloadItems(at:)`。
压力夹具切换数据源后，旧 index path 可能已经超出当前 snapshot，
UIKit 将其判定为非法批量更新并调用 `abort()`。

## 修复方向

- 不再直接使用 collection 的原始 index path 做批量 reload。
- 先通过当前 diffable data source 将 index path 解析为有效 item ID。
- 只对仍存在于当前 snapshot 的 ID 调用 `snapshot.reloadItems`。
- 增加压力数据源切换和前台恢复回归测试。

## 当前状态

已复现。修复已落地：前台恢复只通过当前 diffable snapshot 的有效
item ID 调用 `reloadItems`，不再直接使用旧 index path。待重新出包验证。
