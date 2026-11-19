# 多服务器发布控制面

`deploy/fleet/fleet-production.json` 是集群发布清单。工具不会直接改服务器，
但它会先验证节点、分片所有权、副本覆盖、端口和发布策略，再生成严格的逐片发布波次。

## 校验

```text
node server/tools/fleet-release-plan.js \
  --plan=deploy/fleet/fleet-production.json \
  --canary-shard=0 \
  --out=fleet-release-plan.json
```

正式执行前加 `--require-eligible=1`。存在未验证故障域、容量报告过期、路由哈希
不一致等警告时，命令会以非零状态退出，发布执行器不得继续。

拒绝发布的条件：

- 同一逻辑分片没有 owner，或有多个 owner。
- Cell 主机重复。
- Cell 没有保留全部 7 片副本。
- 端口缺失、重复或不合法。
- 路由计划、发布代码哈希格式错误。
- 同时发布多个 owner 分片。
- 缺少副本追平、容量、健康或自动回滚门禁。

## 发布顺序

1. 所有非 owner 副本按分片滚动发布。
2. 选一个 owner 分片做 canary。
3. 其余 owner 分片逐片发布。
4. 每一步记录 host、cell、shard、service、port、数据根、前置门禁和回滚动作。

一个波次内只能出现一个分片。副本未全部完成前不得进入 owner canary；
任何健康或复制门禁失败都必须停止，不能继续下一波。
