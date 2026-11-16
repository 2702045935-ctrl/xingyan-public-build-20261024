# 七分片 owner 路由原子开关

候选服务默认必须保持关闭：

```text
SHARD_ROUTE_PLAN_ENFORCED=0
chatRoutePlanEnforced=false
chatOwnerForwards=0
```

## 安全约束

- 必须同时提供七个唯一端口。
- 每个端口必须报告相同的运行拓扑和计划哈希。
- 启用请求必须匹配计划内部 hash 与计划文件 SHA256。
- `/__shard/owner-routing` 只接受服务端密钥请求，并需要 `X-Shard-Relay`。
- 任一分片启用失败时，工具会立即向七片发送关闭请求。
- 开关只修改进程内状态；重启后按环境变量恢复 dormant。

启用或停用都使用同一个入口，必须明确二选一。脚本会拒绝已在目标状态的部署，
避免无意义重启或误判：

```text
node tools/shard-owner-switch.js --enable
node tools/shard-owner-switch.js --disable
```

执行前必须完成：

1. 七片 dormant 巡检。
2. 物理影子读零差异。
3. 发布包和路由计划哈希一致。
4. 维护窗口和回滚值班确认。
5. 真机关键链路通过。

任何一项不满足时禁止执行 `--enable`。
