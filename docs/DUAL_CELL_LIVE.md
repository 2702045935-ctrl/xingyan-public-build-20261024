# 双 Cell 当前运行态

更新时间：2026-11-17 09:50（Asia/Shanghai）

## 当前链路

公网 `43.242.194.89:5443` 已切到双 Cell TLS 网关。

| 逻辑分片 | Cell A（43） | Cell B（192） |
| --- | --- | --- |
| 0 | `17080` owner | `19080` replica |
| 1 | `17180` owner | `19180` replica |
| 2 | `17280` owner | `19280` replica |
| 3 | `17380` owner | `19380` replica |
| 4 | `18699` replica | `19480` owner |
| 5 | `18799` replica | `19580` owner |
| 6 | `18899` replica | `19680` owner |

两机使用同一份冻结路由：

- 内部路由哈希：`839c5a4e64e7aa4feb43d49a71de5eb017b0f93918bd05dbacb215dab02da660`
- 计划文件 SHA256：`c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c`
- 物理根：`/opt/xingyan-dual-cell/physical-r1/stage/shards/`
- 物理生成校验：零失败，用户 2365、好友关系 24518、会话 10428、朋友圈 2087、消息线程 27783。

## 当前一致性

`xingyan-dual-cell-file-sync.service` 正在按 owner 方向同步：

- A 的 `0..3` → B 对应分片。
- B 的 `4..6` → A 对应分片。
- 文件级同步只复制 owner 分片目录，不复制整个数据根，避免两机同时重写同一份全局 JSON。

这仍是过渡方案，不是最终事件总线：

- 写请求先由公网网关按用户/会话选 owner。
- 文件同步是 owner 到 replica 的异步复制，不是强一致事务。
- `sync` 目标存在短暂副本延迟；支付和账本不能依赖它做真钱提交。
- 当前没有自动双主切换。故障切换必须停止 owner 写入、确认副本追平、再改网关映射。

## 入口验证

```text
curl -k https://43.242.194.89:5443/api/health
curl -k 'https://43.242.194.89:5443/api/account/state?u=friend852'
```

必须同时满足：

- `ok=true`
- `chatRoutePlanEnforced=true`
- `chatRoutePlanHash` 和 `chatRoutePlanFileHash` 匹配冻结值
- 带 shard 4 用户 token 的 `/api/health` 返回 `port=19480`

## 故障切换边界

不要直接把两机所有分片都改成 active 写。切换前必须先停止旧 owner 写入、确认 owner 分片目录的 replica 差异为零，再切换 gateway 映射。支付、账本、好友关系等高价值路径在完成独立 lease/事务设计前不做自动双写。
