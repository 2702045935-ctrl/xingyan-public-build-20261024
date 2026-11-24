# 热点群路由底座

`server/lib/hot-group-router.js` 把群聊扇出从“一个节点遍历所有收件人”推进到可规划的
多节点批次：

- 小组继续本地扇出；
- 超过阈值进入 batched-cell；
- 万人群或高消息速率进入 dedicated-cell；
- 按 `nodeId + userId` 的稳定哈希分配 Gateway；
- 每批最多 512 个收件人，避免单次跨节点请求过大；
- 按群 ID 固定分区，同一群不会随机漂移；
- 同一用户在一份计划中只出现一次。

当前模块只负责路由计划，不直接替换现有 `fanoutChatMessage`。接入时必须保留：

1. 消息落盘和会话摘要的幂等键；
2. 批次级别的 ack/重试；
3. 慢节点隔离和单批超时；
4. 热点群迁移时的 epoch/fencing；
5. 失败后从 durable outbox 重放。
