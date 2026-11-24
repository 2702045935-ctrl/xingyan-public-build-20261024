# Session Ownership

`server/lib/session-ownership.js` 为 Gateway 的多设备会话提供所有权租约：

- `userId + connectionId` 唯一 claim；
- 同一用户可有多台设备；
- 每台设备记录 Gateway、epoch、TTL、续租和释放；
- 旧 Gateway 不能释放新 epoch；
- 过期连接自动清理；
- 为后续全局 etcd claim 和 Gateway 迁移提供稳定接口。
