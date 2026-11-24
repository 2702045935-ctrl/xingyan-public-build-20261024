# Gateway 集群启动验收

```powershell
node server/tools/gateway-cluster-smoke.js `
  --base-port=5210 `
  --gateway-port=5292
```

工具会：

1. 启动一个隔离业务服务；
2. 启动两个独立 Gateway；
3. 等待 Gateway 上游连接就绪；
4. 检查业务服务目录中的存活节点；
5. 输出节点、Cell 和 endpoint；
6. 无论成功失败都回收子进程和临时数据。

该工具不发送真实聊天消息，不访问生产数据。
