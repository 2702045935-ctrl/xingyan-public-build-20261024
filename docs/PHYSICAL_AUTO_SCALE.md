# 物理分片自动扩容控制面

## 目标

控制面只做一件事：在容量持续超线时，把逻辑分片从旧 owner 平滑迁移到新
Cell，同时保证单写者、副本追平、网关无重启切流和失败自动回滚。

## 已落地的生产链路

1. `single-cell-capacity-collect.js` 在每台 Cell 生成只读容量报告。
2. `fleet-metrics-merge.js` 汇总各 Cell 的内存、CPU、FD、磁盘和 P99。
3. `physical-auto-scale-service.js` 连续采样、检查冷却时间和目标计划有效期。
4. `PhysicalAutoScaleRuntime` 使用跨进程锁，避免两个扩容任务并发。
5. `PhysicalAutoScaleController` 生成固定逻辑分片迁移计划。
6. `PhysicalScaleProductionAdapters` 通过 SSH 执行远程 Cell 操作。
7. `fleet-node-control.js` 在目标机执行副本同步、清单哈希、单分片冻结、
   owner 路由、健康检查和网关路由文件原子写入。
8. TLS 网关通过 `SIGHUP` 热加载跨主机 owner 地址，不重启监听进程，
   不断开现有连接，也不依赖本机端口隧道。
9. owner 验证后原子切换复制拓扑；各 Cell 的复制守护进程只复制当前计划中的
   owner 分片。
10. 任一步失败时，先恢复复制计划和旧路由，再热加载网关，再恢复租约和旧 owner。
11. 只有完整迁移和 30 分钟长稳都通过，才提升目标 Fleet 计划并清除压力计数。

## 安全门禁

- 目标计划必须 `deploymentEligible=true`，故障域不能是 `unverified`。
- 每个逻辑分片始终只有一个 owner。
- 只允许单 owner 分片在途。
- 指标文件超过 180 秒直接拒绝自动扩容。
- 目标计划超过配置时限直接拒绝。
- 任意 Cell 不健康时不触发扩容。
- `execute=false` 时只生成判断结果，不执行远程操作。
- 同一时间只允许一个控制面进程持有任务锁。

## 启用步骤

```bash
cp deploy/fleet/physical-auto-scale.service /etc/systemd/system/
cp deploy/fleet/physical-replication-sync.service /etc/systemd/system/
cp deploy/fleet/physical-auto-scale.example.json /etc/xingyan-dual-cell/auto-scale.json
install -m 0600 deploy/fleet/fleet-production.json \
  /var/lib/xingyan-dual-cell/current-fleet.json
systemctl daemon-reload
systemctl enable --now physical-replication-sync.service
systemctl enable --now physical-auto-scale.service
```

初次部署保持 `execute=false`。完成真实 2→4 Cell 副本、故障域、SSH
免密、网关热加载和回滚演练后，再改为 `execute=true`。

## 指标文件

```bash
node server/tools/fleet-metrics-merge.js \
  --cell=cell-a-43:/var/lib/xingyan-dual-cell/cell-a-capacity.json \
  --cell=cell-b-192:/var/lib/xingyan-dual-cell/cell-b-capacity.json \
  --latency=cell-a-43:180 \
  --latency=cell-b-192:210 \
  --out=/var/lib/xingyan-dual-cell/fleet-metrics.json
```

控制面不自行猜测负载；指标过期时宁可不扩容，也不使用旧数据误切生产。

## 验收边界

自动测试覆盖计划、锁、陈旧输入、生产适配器、网关热加载和失败回滚。
仓库内没有新增物理主机，因此真实 2→4 主机部署、跨故障域副本追平和生产
流量长时间切流仍需在目标环境执行，不能用模拟测试替代。
