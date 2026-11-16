# 七分片写冻结与 fencing

写冻结用于物理分片切换窗口，不属于日常维护开关。

## 行为

- HTTP：冻结后只放行 `GET/HEAD/OPTIONS` 和冻结控制接口，其余写请求返回 `503`。
- WebSocket：放行 `ping`、通话和直播信令；聊天发送、已读、拍一拍、回执等写操作返回
  `SHARD_WRITE_FROZEN`。
- 健康接口返回 `writeFrozen`、`fenceEpoch` 和 `writeFreezeReason`。
- 每次冻结或解冻必须递增 fencing epoch，旧 epoch 请求会被拒绝。
- 七片必须共享相同的路由计划文件 SHA256 和内部 hash。
- 任一分片切换失败时，控制器会尝试把所有分片恢复到解冻状态。

## 命令

```text
node tools/shard-write-freeze.js --freeze --reason=physical-shard-cutover
node tools/shard-write-freeze.js --unfreeze
```

冻结不是持久化状态，进程重启后默认解除。切写流程必须保证旧进程已经停止，且新进程
只读取自己的物理分片根目录。

## 切写顺序

1. 运行所有前置门禁。
2. 七片同时冻结并确认 epoch 一致。
3. 从冻结后的线上数据生成最终快照。
4. 重建并验收物理分片，影子差异必须为零。
5. 切换进程数据根目录和 owner 模式。
6. 七片健康、真机读写和回滚点全部通过后，按新 epoch 解冻。

任一步失败都必须停止，不允许只解冻部分分片。
