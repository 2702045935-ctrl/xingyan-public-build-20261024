# 单 Cell 容量门禁

适用场景：当前只有 `192.140.179.176` 一台业务机，不能做双 Cell。

维护窗口必须采集真实主机和 7 个分片进程数据，再运行：

```text
node server/tools/single-cell-capacity-audit.js \
  --input=<容量输入 JSON> \
  --out=<容量报告>
```

输入模板：`docs/SINGLE_CELL_CAPACITY_INPUT.template.json`。

正式机器上可直接只读采集：

```text
node server/tools/single-cell-capacity-collect.js \
  --manifest=/opt/xingyan-mainline/app/shard-runtime-production.json \
  --data-dir=/opt/xingyan-mainline/data \
  --out=<容量采集与门禁报告>
```

采集器读取 systemd MainPID、`/proc/<pid>/status`、`/proc/<pid>/fd`、
`/proc/meminfo`、`/proc/loadavg` 和数据目录 `statfs`。它不修改服务、配置或数据。

## 默认阈值

| 指标 | 默认上限 |
| --- | --- |
| 内存已使用 | 75% |
| 最小空闲内存 | 512MB |
| 每核 load1 | 0.8 |
| 磁盘已使用 | 80% |
| inode 已使用 | 80% |
| 单进程文件描述符 | 50000 |

还要求 7 个分片 PID 全部存在、互不重复、RSS 有效，并且 0–6 每片都有数据。

## 发布规则

1. 容量报告必须 `ok=true`。
2. 报告必须包含 0–6 全部 7 片、有效 PID、零失败项和稳定指纹。
3. 报告采集时间距维护发布待命不能超过 30 分钟。
4. 报告指纹写入维护记录。
5. 维护中心必须粘贴完整容量报告，单纯勾选不能代替报告。
6. 未通过时不允许进入休眠发布。
7. 容量门禁不等于容量压测；它只防止在没有余量时继续发布。
