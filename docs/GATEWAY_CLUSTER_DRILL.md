# Gateway Cluster Drill

运行：

```powershell
node server/tools/gateway-cluster-drill.js `
  --members=10000 `
  --out=gateway-cluster-drill.json
```

演练内容：

1. 生成万人群成员；
2. 按 Gateway 生成批次计划；
3. 模拟 `gw-b` 故障；
4. durable outbox 保持 pending；
5. 时间窗口过后自动重试；
6. 验证最终 ack、pending 清零和 publishId 不重复。

当前使用模拟 bus，不向生产 Gateway 发送真实消息。后续会替换为真实 Gateway
集群和故障注入器，作为 canary 放量前的固定门禁。
