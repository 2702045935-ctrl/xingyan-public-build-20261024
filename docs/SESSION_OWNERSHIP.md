# Session Ownership

`server/lib/session-ownership.js` 为 Gateway 的多设备会话提供所有权租约：

- `userId + connectionId` 唯一 claim；
- 同一用户可有多台设备；
- 每台设备记录 Gateway、epoch、TTL、续租和释放；
- 旧 Gateway 不能释放新 epoch；
- 过期连接自动清理；
- 为后续全局 etcd claim 和 Gateway 迁移提供稳定接口。

`server/lib/session-ownership-etcd.js` 已提供全局 etcd 模式：

- key：`/xingyan/gateway-sessions/{userId}/{connectionId}`；
- claim 使用 CAS，旧 Gateway 不能覆盖新 epoch；
- TTL 到期自动清理；
- release 校验 gatewayId 和 epoch；
- Gateway 设置 `GATEWAY_SESSION_BACKEND=etcd` 后通过主服务内部
  `/__gateway/sessions/claim|renew|release` 访问。
