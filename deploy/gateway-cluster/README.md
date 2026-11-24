# Gateway 集群部署包

这是长连接底座的部署骨架，不包含真实密钥和节点地址。

## 前提

- Node 24
- 三节点 etcd 或已有 etcd v2 API
- 主服务已支持 `GATEWAY_ADMIN_SECRET`
- 网关机器到主服务内网可达

## 安装

1. 将 `server/gateway-server.js` 和 `server/lib/` 放到发布目录；
2. 将模板复制到 `/etc/xingyan-gateway/<node>.env`；
3. 每个实例设置不同 `GATEWAY_PORT`、`GATEWAY_NODE_ID`、`GATEWAY_CELL_ID`；
4. 将服务文件安装到 `/etc/systemd/system/xingyan-gateway@.service`；
5. 三台机器分别启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now xingyan-gateway@gateway-a
sudo systemctl enable --now xingyan-gateway@gateway-b
sudo systemctl enable --now xingyan-gateway@gateway-c
```

## 主服务灰度

主服务先使用 `canary.env.example`，保持：

```text
GATEWAY_FANOUT_MODE=canary
GATEWAY_FANOUT_CANARY_PERCENT=1
```

观察：

- `/api/health` 的 `gatewayFanout.outbox.pending`
- `gatewayFanout.failures`
- `gatewayFanout.canary`
- 每台 Gateway `/health`
- `/__gateway/directory` 的 liveNodes

只有 outbox pending 回落、失败率低于阈值、Gateway 存活稳定，才逐步调整：

```text
1 -> 5 -> 20 -> 50 -> 100
```

## 回滚

```text
GATEWAY_FANOUT_MODE=off
```

或将百分比设为 `0`。已经落到 outbox 但未完成的任务会继续由 dispatcher 处理；
不要让 Gateway 在 outbox 仍有 pending 时直接删数据。
