# Gateway 目录与独立网关底座

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

当前已经增加可选独立 Gateway：

```text
server/gateway-server.js
```

客户端仍然连接原有 `/ws` 协议；独立 Gateway 启动后：

1. 客户端 WebSocket 原始帧被装进 `gateway-multiplex` 信封；
2. 多个客户端复用同一条上游 Gateway 通道；
3. 主服务通过虚拟 socket 继续复用原 `handleSocket` 逻辑；
4. Gateway 注册到主服务目录并每 10 秒心跳；
5. Gateway 摘流时停止接入新客户端，已有连接不主动切断。

启动示例：

```powershell
$env:GATEWAY_PORT = "5290"
$env:GATEWAY_UPSTREAM_WS = "ws://127.0.0.1:5180/__gateway/upstream"
$env:GATEWAY_BACKEND_HTTP = "http://127.0.0.1:5180"
$env:GATEWAY_ADMIN_SECRET = "<same-internal-secret>"
node server/gateway-server.js
```

这不是完整的消息总线。下一条链路必须把上游通道替换为跨节点发布订阅，
并接入 etcd/专用目录服务；当前仅证明独立 Gateway 可以注册、复用连接并转发原始帧。
