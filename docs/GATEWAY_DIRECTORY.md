# Gateway 目录与路由底座

`server/lib/gateway-directory.js` 是亿级长连接底座第二层：

- Gateway 节点注册和心跳；
- 容量水位、cell、故障域和 endpoint 元数据；
- 用户到 Gateway 的短期 claim 租约；
- 同一用户跨节点互斥，支持 forced takeover 和 epoch；
- 过期 claim 回收；
- rendezvous hash + 负载评分选择节点；
- 可替换本地目录后端，不改变上层路由接口。

当前默认仍是进程内目录，不能把单进程 Map 当成全局一致性目录。生产版必须把
`register/heartbeat/claim/renew/release/reapExpired` 接到 etcd 或专用目录服务，
并把目录调用放在连接建立和迁移事务中。

## 指标

`GatewayDirectory.snapshot()` 输出节点、存活节点、连接 claim、注册/领取/释放/过期数量和
每个节点的负载水位。

## 下一层

1. 独立 Gateway 服务接收客户端 WebSocket；
2. 目录后端接入 etcd lease；
3. Gateway 间发布订阅和信封协议；
4. 跨 Gateway 消息投递、断线重连和幂等；
5. 百万连接、跨 Cell 摘流和故障接管验收。
