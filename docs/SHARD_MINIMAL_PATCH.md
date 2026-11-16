# 分片底座最小补丁

禁止把候选分支的完整 `server.js` 直接覆盖正式稳定版。正式维护使用锚点补丁：

```text
node server/tools/shard-route-patch.js \
  --source=<正式当前 server.js> \
  --out=<新的候选 server.js> \
  --report=<补丁报告>
```

默认要求正式源码 SHA256 为：

```text
cb937047456b6c6bf4aa1b174b4d1edb397e54c1e47ff60f6ca0341b4215007c
```

补丁只注入八处：

1. 路由和运行身份模块引用。
2. 路由计划及运行 manifest 启动校验。
3. 聊天 owner 端口计算和跨片转发。
4. 客户端聊天操作的 owner 转发闸门。
5. 健康接口的分片、计划和转发字段。
6. `/__shard/chat-action` 内部转发接口。
7. `/__shard/owner-routing` 七片原子开关接口。
8. `/__shard/write-freeze` 七片写冻结与 fencing 接口。

以下任一情况直接失败：

- 源文件 SHA256 不一致。
- 已包含路由计划代码。
- 任一锚点缺失或出现多次。
- 输出路径与源文件相同或已存在。
- 生成后的文件不能通过 `node --check`。

补丁报告会列出所需 helper 文件和每个文件的 SHA256。helper 必须复制到候选目录对应位置，
不能在共享目录就地覆盖。

补丁生成的只是休眠候选。正式执行仍必须逐片领取、执行、回报和健康验收。

## 候选目录装配

```text
node server/tools/shard-minimal-release.js \
  --server-source=<正式稳定 server.js> \
  --out-dir=<新的空候选目录> \
  --expected-sha256=cb937047456b6c6bf4aa1b174b4d1edb397e54c1e47ff60f6ca0341b4215007c
```

装配器会：

1. 校验稳定源码 SHA256。
2. 生成最小补丁 `server.js`。
3. 从维护、容量、物理对账、影子读取和发布门禁的入口文件递归收集依赖。
4. 只复制实际依赖，不复制数据、备份、输出目录或稳定版无关模块。
5. 为每个文件记录 SHA256。
6. 生成 `release-manifest.json` 和整体内容哈希。
7. 先写临时目录，全部成功后原子改名为正式候选目录。

目标目录必须不存在。装配失败只清理自己的临时目录，不触碰现有发布。

当前装配器同时包含独立维护页：

```text
/shard-maintenance.html?k=<后台暗号>
```

它不会覆盖稳定版 `manage.html`。页面仍受后台 IP 白名单、后台暗号和超级管理员 API
权限保护，只提供单分片发布、容量采集、健康验收、批准和回滚。

## 安装到新发布目录

```text
node server/tools/shard-release-install.js \
  --overlay=<最小发布包目录> \
  --base-app=/opt/xingyan-mainline/app \
  --out-dir=/opt/xingyan-mainline/releases/<新版本> \
  --expected-base-sha256=cb937047456b6c6bf4aa1b174b4d1edb397e54c1e47ff60f6ca0341b4215007c
```

安装器要求：

1. 基础稳定 `server.js` 哈希完全一致。
2. 发布包 `productionEligible=true`。
3. 发布包记录的基础源码哈希与当前基础一致。
4. 所有发布文件 SHA256 正确。
5. 输出目录不存在且不与输入目录重叠。

安装时先把基础应用复制到临时目录，再覆盖最小发布文件，最后校验安装后的
`server.js` 哈希。成功后原子改名并生成 `staged-install-report.json`。

原 `/opt/xingyan-mainline/app` 不会被修改。预览包因
`productionEligible=false` 会被安装器直接拒绝。

正式候选目录还会包含：

- `shard-runtime-production.json`
- `shard-topologies.json`
- `run-shard-candidate.sh`

候选启动脚本固定使用正式冻结计划，并设置
`SHARD_ROUTE_PLAN_ENFORCED=0`。它只用于显式启动候选进程，不会自动替换
`/opt/xingyan-mainline/run-shard.sh` 或现有 systemd 服务。
