# Gateway 批量投递契约

`server/lib/gateway-fanout.js` 负责把已经按用户分组的计划发到各 Gateway：

- 每个 Gateway 只接收自己负责的 `userIds`；
- 请求带 `publishId`，后续由 Gateway 做去重；
- 单节点失败按配置重试；
- 返回每个节点的 delivered/error，不把部分失败伪装成成功；
- 单次请求有超时和批次上限。

Gateway 侧 `/__gateway/publish` 目前是内部接口，必须带
`GATEWAY_ADMIN_SECRET`，只对已认证连接发送 WebSocket 文本帧。

默认 `GATEWAY_FANOUT_MODE=off`。设置 `GATEWAY_FANOUT_MODE=shadow` 后，
群消息路径只做路由计划和 `dryRun` 投递，不改变现有真实投递结果，用于验证节点选择、
批次大小、回执和故障指标。确认无重复、无丢失后再切换 live 模式。

设置 `GATEWAY_FANOUT_MODE=live` 后，热点群消息会先进入
`fanout-outbox.jsonl`，由 dispatcher 批量发给 Gateway；本地已由 Gateway 承载的
虚拟连接会跳过旧 `sendTo`，避免双发。没有可用 Gateway 时自动回退本地链路。

灰度切流：

```text
GATEWAY_FANOUT_MODE=canary
GATEWAY_FANOUT_CANARY_PERCENT=1
```

canary 按群 ID 的稳定哈希选择，不随进程重启漂移。建议依次使用
`0 -> 1 -> 5 -> 20 -> 50 -> 100`，每一步观察 outbox pending、Gateway ack、
P99 和重复投递指标。只有 `live` 或 `canary` 且实际选中时才跳过本地 Gateway 虚拟连接。

接入主消息路径前还需要补：

1. durable outbox 和批次 ack；
2. publishId 幂等表；
3. 慢消费者背压；
4. 热点群专用 Cell 的 lease；
5. 批次级重试与死信队列。
