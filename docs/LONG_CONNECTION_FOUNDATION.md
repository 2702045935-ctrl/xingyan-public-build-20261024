# 长连接底座第一层

这一层先解决“每个节点知道自己还能接多少连接、何时应该摘流、何时拒绝新连接”的问题。
它不改变现有 WebSocket 消息协议，也不把单机内存伪装成分布式状态。

## 当前模块

`server/lib/connection-governor.js`

- 总连接容量上限；
- 单用户连接上限；
- 单 IP 连接上限；
- 软水位和硬水位；
- drain 摘流状态；
- accepted/rejected/released 指标；
- 释放幂等，连接关闭不会重复减计数。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | ---: | --- |
| `WS_MAX_TOTAL_CONNECTIONS` | `100000` | 单进程硬上限，仅作为内存保护，不等于生产 SLA |
| `WS_MAX_CONNECTIONS_PER_USER` | `4` | 一个账号允许的设备连接数 |
| `WS_MAX_CONNECTIONS_PER_IP` | `WS_MAX_PER_IP`（默认 60） | 单 IP 连接保护 |
| `WS_SOFT_LOAD_RATIO` | `0.85` | 软水位，供调度和告警使用 |
| `GATEWAY_HEARTBEAT_MS` | `10000` | Gateway 目录心跳间隔 |

## 接口

- `/api/health` 增加 `gateway` 快照；
- `POST /__gateway/drain` 需要 `GATEWAY_ADMIN_SECRET`，用于滚动发布时停止接收新连接；
- `POST /__gateway/resume` 恢复接收；
- 拒绝连接返回 `503` / `Retry-After`，不把容量问题伪装成普通业务错误。

## 这不是亿级完成

这只解决单节点的连接治理。要支持百万/亿级并发，还必须继续完成：

1. 独立 WebSocket Gateway 层；
2. 跨节点连接目录和用户路由；
3. 发布订阅/消息总线；
4. 热群隔离与跨片扇出；
5. 媒体对象存储和异步转码；
6. 多 Cell 调度、故障接管和自动扩缩容；
7. 真实生产多机 soak 和故障演练。
