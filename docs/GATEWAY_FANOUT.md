# Gateway 批量投递契约

`server/lib/gateway-fanout.js` 负责把已经按用户分组的计划发到各 Gateway：

- 每个 Gateway 只接收自己负责的 `userIds`；
- 请求带 `publishId`，后续由 Gateway 做去重；
- 单节点失败按配置重试；
- 返回每个节点的 delivered/error，不把部分失败伪装成成功；
- 单次请求有超时和批次上限。

Gateway 侧 `/__gateway/publish` 目前是内部接口，必须带
`GATEWAY_ADMIN_SECRET`，只对已认证连接发送 WebSocket 文本帧。

接入主消息路径前还需要补：

1. durable outbox 和批次 ack；
2. publishId 幂等表；
3. 慢消费者背压；
4. 热点群专用 Cell 的 lease；
5. 批次级重试与死信队列。
