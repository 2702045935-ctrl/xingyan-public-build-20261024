# Gateway Session Cell

`server/lib/session-cell.js` 把 Gateway 的连接状态从散落 Map 收成独立会话单元：

- connectionId -> client；
- userId -> 多设备 connectionId；
- 连接打开、绑定用户、关闭回收；
- 用户多设备查询；
- 单 Cell 容量水位；
- drain/resume；
- 连接和用户统计。

它是后续做 Gateway 会话归属、跨 Gateway 迁移和 session fencing 的基础。

`server/lib/session-ownership.js` 已接在 Session Cell 之上，为
`userId + connectionId` 记录 Gateway、TTL、epoch、续租和释放；同一用户的不同设备
可以分别归属不同 Gateway，旧 epoch 不能释放新会话。
