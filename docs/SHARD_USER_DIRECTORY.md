# 分片用户目录

用户目录是 `derived-rebuild` 索引，只保存路由所需的最小字段：

- 用户 ID
- owner shard
- 规范化用户名
- 规范化手机号
- 规范化邮箱

它不保存用户完整资料，不是用户权威数据。用户名、手机号、邮箱必须全局唯一；任一别名
重复或 owner 与冻结计划不一致都会拒绝生成。

## 生成

```text
node server/tools/shard-user-directory.js \
  --users=<users.json> \
  --route-plan=<route-plan.json> \
  --out=<user-directory.json>
```

目录内包含冻结计划 hash、分片数量和每片用户数量，可在每个分片启动前校验。

## 使用边界

目录只解决“某个登录别名属于哪个用户、该用户在哪一片”。用户资料读写仍必须进入唯一
owner，不得把目录当成用户主数据。当前版本完成的是索引生成和校验，尚未把登录与资料接口
接入跨片 owner 路由。
