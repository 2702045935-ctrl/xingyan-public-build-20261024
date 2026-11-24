# Fanout Outbox

`server/lib/fanout-outbox.js` 为跨 Gateway 扇出提供持久化事务边界：

1. 消息落盘、会话摘要更新后，将 fanout 任务追加到 outbox；
2. 任务按 `publishId` 幂等；
3. 发送前记录 attempt；
4. Gateway 全部 ack 后才标记 acked；
5. 网络失败写入可重试时间和错误；
6. 进程重启时从追加日志恢复 pending/acked 状态；
7. acked 记录可在容量水位下回收。

它不是消息本身的事实源，而是“已持久化消息 -> 跨节点投递”的可靠转交层。
