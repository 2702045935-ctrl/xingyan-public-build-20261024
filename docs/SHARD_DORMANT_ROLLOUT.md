# 分片休眠补丁放行单

本放行单只负责把已通过验证的代码和冻结路由计划安全加载到正式 7 片。
它不授权数据迁移、分片重排、稳定包覆盖或直接切换线上目录。

## 维护中心

管理后台入口：`/manage.html#shardmaintenance`，仅超级管理员可见。

维护中心默认只保存控制状态，不直接执行 `systemctl`。它强制以下规则：

1. 同时只能存在一个未结束的发布。
2. 发布前五项检查必须全部确认。
3. 每次只能请求当前一个分片，不能批量提交 7 片。
4. 健康证据必须匹配冻结计划内部哈希、计划文件 SHA256、运行 manifest、拓扑、
   服务名和端口。
5. 当前片健康通过后，也必须再次输入确认口令和后台密码，才解锁下一片。
6. 任何健康失败立即暂停；下一片和其他分片保持 `pending`。
7. 回滚状态单独记录，不覆盖历史发布记录。
8. 多个分片进程共享状态文件时使用排他锁，不能同时推进两个分片。

## 冻结输入

| 项目 | 冻结值 |
| --- | --- |
| 业务机 | `192.140.179.176` |
| 运行拓扑 | `server-b-mainline-shards-7` |
| 后端端口 | `7080, 7180, 7280, 7380, 7480, 7580, 7680` |
| 服务 | `xingyan-mainline-shard@0-6.service` |
| 正式数据目录 | `/opt/xingyan-mainline/data` |
| 稳定代码 SHA256 | `cb937047456b6c6bf4aa1b174b4d1edb397e54c1e47ff60f6ca0341b4215007c` |
| 稳定运行 manifest | `f7afcdef3bd1d51ef7b50f58650009693397686faaaa31da6738ed96aa4f0f44` |
| 冻结路由计划哈希 | `839c5a4e64e7aa4feb43d49a71de5eb017b0f93918bd05dbacb215dab02da660` |
| 冻结计划文件 SHA256 | `c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c` |
| 冻结计划对象数 | 用户 `2365`，会话 `10428`，合计 `12793` |

任何一项不一致都必须停止，不允许通过修改计划内容“让它通过”。

## 阶段 0：候选验证

1. 在隔离目录执行语法、启动预检和完整回归。
2. 7 分片测试必须覆盖休眠加载、激活加载、owner 重启、跨片转发、并发发送和序号唯一性。
3. 候选包必须记录代码 SHA256、测试时间、操作者和测试报告 SHA256。
4. 未全部通过的候选包不得复制到业务机。

最低回归集合：

```text
node --check server/server.js
node server/test/chat-route-plan.test.js
node server/test/chat-owner-routing.test.js
node server/test/chat-actions.test.js
node server/test/message-sequence-audit.test.js
node server/test/message-sequence-repair-plan.test.js
node server/test/message-sequence-repair-apply.test.js
node server/test/upload-reference-repair-plan.test.js
node server/test/upload-reference-quarantine-apply.test.js
node server/test/call-audio-relay.test.js
node server/test/call-cross-shard.test.js
node server/test/shard-*.test.js
```

## 阶段 1：只读盘点

在维护窗口开始前记录：

1. 7 个 service 的 active 状态和 PID。
2. 7 个 backend 端口的健康响应。
3. 当前 `server.js` 文件 SHA256。
4. 当前运行 manifest、运行拓扑和服务名。
5. `/opt/xingyan-mainline/data` 的磁盘空间、inode 和最近一次完整备份标识。
6. 冻结计划文件的绝对路径、文件 SHA256 和内部 `hash`。

任一服务异常、PID 缺失、端口错位、数据目录不足或计划无法校验时，不进入复制阶段。

## 阶段 2：候选副本

1. 候选代码必须进入新的版本目录，不覆盖 `/opt/xingyan-mainline/app`。
2. 冻结计划复制到只读发布目录，复制后重新计算文件 SHA256。
3. 新目录只包含代码和只读配置，不复制或移动业务数据。
4. 保留当前稳定代码、当前 service 配置和当前计划文件的绝对回滚路径。

## 阶段 3：休眠加载

7 片使用同一份服务配置启动候选代码：

```text
SHARD_ROUTE_PLAN_FILE=<冻结计划文件的绝对路径>
SHARD_ROUTE_PLAN_FILE_SHA256=c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c
SHARD_ROUTE_PLAN_ENFORCED=0
```

此时计划会被校验并加载，但聊天写入仍使用旧实现。7 片健康响应必须同时满足：

```text
chatRoutePlanHash   = 839c5a4e64e7aa4feb43d49a71de5eb017b0f93918bd05dbacb215dab02da660
chatRoutePlanFileHash = c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c
chatRouteTopologyId = server-b-mainline-shards-7
chatRoutePlanEnforced = false
runtimeManifestHash = f7afcdef3bd1d51ef7b50f58650009693397686faaaa31da6738ed96aa4f0f44
```

任一进程启动失败、计划哈希或计划文件 SHA256 不一致、拓扑不一致、端口不等于
`SHARD_BASE_PORT + SHARD_ID * 100` 或 7 片字段不一致，立即全部回滚到稳定版本。

7 片休眠验收命令：

```text
node server/tools/shard-runtime-audit.js \
  --manifest=/opt/xingyan-mainline/app/shard-runtime-production.json \
  --topology=/opt/xingyan-mainline/app/shard-topologies.json \
  --route-plan=<冻结计划文件的绝对路径> \
  --route-plan-file-sha256=c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c \
  --require-route-dormant
```

休眠阶段还要确认：

- 7 片候选代码 SHA256 完全一致。
- 7 个旧 PID 已被明确记录，替换后的 PID 均为 active。
- 公网登录、会话读取、单聊发送和群聊发送正常。
- 消息序号无重复、无断档、无跨 owner 双写。
- 冻结计划文件在候选代码目录中保持只读。

## 阶段 4：受控激活

只有休眠阶段全部通过后才允许进入激活：

1. 确认 `activeCalls=0`、`ringingCalls=0`。
2. 再次确认 7 片加载的是同一计划哈希和同一拓扑。
3. 将 `SHARD_ROUTE_PLAN_ENFORCED` 改为 `1`，不修改计划文件。
4. 按分片受控替换进程；替换期间旧实现和新实现计算出的 owner 必须相同。
5. 7 片健康响应中的 `chatRoutePlanEnforced` 必须全部为 `true`。
6. 连续发送、并发发送、owner 重启和跨片转发复测通过后，才结束维护窗口。

激活后把休眠验收命令的最后一项改为 `--require-route-enforced`，再次全部通过才允许结束维护窗口。

## 回滚

回滚只做三件事：

1. 将 `SHARD_ROUTE_PLAN_ENFORCED` 改回 `0`。
2. 恢复上一版 service 配置或上一版候选目录。
3. 按原 PID、端口、代码 SHA256 和 manifest 验证 7 片恢复。

回滚不需要修改 `/opt/xingyan-mainline/data`，不允许删除稳定备份，不允许改写冻结计划。

## 硬禁止

- 在休眠验证未通过时直接激活。
- 同时进行代码发布、数据迁移、分片扩容和支付账本变更。
- 用启动参数临时绕开计划哈希、拓扑或端口校验。
- 忽略计划文件字节 SHA256 不一致，只核对计划内部哈希。
- 为某一分片单独生成不同的路由计划。
- 用候选数据目录替换 `/opt/xingyan-mainline/data`。
- 把稳定版 `B2611151628 / bc09897` 当作本次候选代码继续改写。
