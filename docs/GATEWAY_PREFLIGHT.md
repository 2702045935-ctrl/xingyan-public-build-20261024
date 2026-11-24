# Gateway 切流前置检查

```powershell
node server/tools/gateway-cluster-preflight.js `
  --backend=https://api.example.com `
  --secret=... `
  --directory-backend=etcd `
  --fanout-mode=canary `
  --canary-percent=1 `
  --gateways=https://gw-a.example.com,https://gw-b.example.com,https://gw-c.example.com `
  --out=gateway-preflight.json
```

检查项：

- 主服务健康；
- 目录接口可用且鉴权正确；
- 至少两个存活 Gateway；
- 每个 Gateway 的健康和上游通道状态；
- canary/live 模式与百分比合法；
- 密钥和 backend 地址齐全。

报告中有任何 blocker 时退出码为 `1`，部署流水线必须停止，不允许 live 放量。
