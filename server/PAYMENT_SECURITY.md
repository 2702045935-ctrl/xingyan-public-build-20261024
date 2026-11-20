# 星言真钱支付核心

## 当前边界

- 钱包余额、双边账本、设备令牌、支付意图、支付事件、转账单、资金订单、
  幂等命令和 outbox 统一存放在 `data/payments.sqlite3`。
- SQLite 使用 `WAL`、`synchronous=FULL`、`foreign_keys=ON`、
  `busy_timeout=10000` 和 `BEGIN IMMEDIATE`。余额、账本、单据及待发事件
  在同一个事务内提交。
- 支付事件和账本均使用 HMAC 哈希链，启动时校验前序哈希和链尾。
- 真钱模式只接受 Secure Enclave 设备签名。密码转账和旧的无签名转账路径
  在 `enforce` 模式下全部拒绝。
- 原始卡号、CVV 和完整银行卡号不进入支付数据库。设备私钥只保存在
  Secure Enclave，服务端只保存公钥。
- 反洗钱自动拦截默认关闭。当前产品要求下，`AML_RUNTIME_ENABLED=0`。

## 真实资金流程

### 充值

1. App 创建充值订单，数据库先记录为 `pending`，不会增加余额。
2. 持牌支付机构返回 `providerRef`、收银台地址或二维码。
3. 机构服务端回调星言，回调必须在 5 分钟时间窗内通过 HMAC-SHA256 验签。
4. 回调事件按 `provider + providerEventId` 去重。
5. 充值成功后，余额和账本在同一个 SQLite 事务内入账。

重复回调、网络重试和进程重启都不会重复入账。

### 提现

1. 创建提现订单时，本金和手续费在同一个事务内从零钱转入
   `system:payout-pending` 和 `system:fee-revenue`。
2. 持牌支付机构通过签名回调确认成功或失败。
3. 成功时清除待结算账户；失败时本金和手续费原路退回用户零钱。
4. outbox 负责机构下单重试，已经冻结的资金不会因 App 重试再次扣除。

### 转账和扫码付款

- 单聊转账必须完成设备令牌绑定、单次 nonce、支付意图签名和原子 capture。
- 扫码付款在同一事务内完成付款方扣款、收款方入账和转账单创建。
- 聊天消息通过 outbox 发送。即使消息发送暂时失败，资金状态也有稳定引用，
  不会因为客户端反复点击重复扣款。

## 启动条件

必须使用 Node.js 24 或更高版本，因为支付数据库使用内置 `node:sqlite`。

```text
PAYMENT_REAL_MONEY_MODE=enforce
PAYMENT_DATABASE_MODE=sqlite
PAYMENT_KEY_ID=<key id>
PAYMENT_KEY_BASE64=<32-byte base64 secret>
PAYMENT_PROVIDER_NAME=<licensed provider name>
PAYMENT_PROVIDER_BASE_URL=<provider bridge https origin>
PAYMENT_PROVIDER_API_KEY=<provider request signing secret>
PAYMENT_PROVIDER_WEBHOOK_SECRET=<provider webhook secret>
AML_RUNTIME_ENABLED=1
```

生产环境建议用 systemd credentials、KMS 注入文件或 HSM 挂载文件提供密钥：

```text
PAYMENT_KEYS_FILE=/run/credentials/chris.service/payment-keys.json
```

`payment-keys.json` 支持多版本密钥和 `PAYMENT_ACTIVE_KEY_ID` 轮换。不要把支付
密钥写入仓库、聊天记录或 shell 历史。

支付机构桥接地址必须是 HTTPS。只有 `CHRIS_LOCAL_ONLY=1` 的本地机构沙箱
可额外设置 `PAYMENT_PROVIDER_ALLOW_HTTP=1`，生产环境不得设置该变量。
机构请求默认 10 秒超时，可通过 `PAYMENT_PROVIDER_TIMEOUT_MS` 调整，
允许范围 1000～60000 毫秒。

任何一项缺失时：

- 转账等内部钱包操作仍必须经过 SQLite 支付意图；缺少数据库时返回 503。
- 充值和提现直接返回 503，不会出现先加钱或先扣钱再等接口的情况。
- `GET /api/payment/status` 的 `realMoneyReady=false`，并通过 `blockers`
  返回未通过项，例如支付密钥、AML、数据库自检或机构 HTTPS。

## 支付机构桥接协议

持牌支付机构或内部合规支付网关需要提供以下 HTTPS 接口：

```text
POST /v1/deposits
POST /v1/payouts
GET  /v1/settlements?date=YYYY-MM-DD
```

请求头：

```text
x-xingyan-timestamp: Unix milliseconds
x-xingyan-signature: base64url(HMAC-SHA256(apiKey, timestamp + "\n" + body))
```

充值 / 提现回调发往：

```text
POST /api/payment/provider/webhook
```

回调头使用 `PAYMENT_PROVIDER_WEBHOOK_SECRET` 计算同样的 HMAC。请求体至少包含：

```json
{
  "id": "provider-event-id",
  "type": "deposit.succeeded",
  "data": {
    "kind": "deposit",
    "orderId": "fund_xxx",
    "status": "succeeded",
    "providerRef": "provider-reference",
    "amountCents": 1000,
    "feeCents": 0,
    "currency": "CNY",
    "failureCode": ""
  }
}
```

回调金额、手续费、币种、订单类型和状态必须与本地资金单完全一致；不一致时
返回 409，且不会登记为已处理或改变余额。成功回调必须提供 `providerRef`。

## 逐日对账

后台接口：

```text
GET /api/ops/payments/reconcile
GET /api/ops/payments/settlement?date=YYYY-MM-DD
GET /api/ops/payments/settlement/incidents?status=open
POST /api/ops/payments/settlement/incidents/:id/resolve
GET /api/ops/payments/disputes?status=open
POST /api/ops/payments/disputes
POST /api/ops/payments/disputes/:id/resolve
POST /api/ops/payments/disputes/:id/finalize
```

机构结算文件会逐笔比对订单号、金额、手续费、币种和状态。差异只生成报告，
不会自动改钱。存在差异时同事务生成人工对账工单，必须填写处理说明后才能
结案；重复结案按幂等返回。

支付争议使用独立台账，绑定支付意图、机构争议号、争议金额和冻结前状态。
开启争议时支付意图与争议记录在同一事务内变为 `disputed`；同一机构争议号
重复回调只返回原记录，不会重复冻结。未结争议会让 `realMoneyReady=false`。
处置必须填写处理人、至少 8 个字的处理说明和 `won`、`withdrawn`、
`accepted`、`lost` 之一。`won` / `withdrawn` 可恢复原意图状态；
`accepted` / `lost` 会保持资金冻结并进入 `adjustment_required`，只有绑定一笔
争议发生后已幂等落账的核销流水才能通过 `finalize` 解冻。系统不会自动改钱，
退款、扣款和冲正仍必须使用独立幂等账本分录并由人工复核。

## 首次切换

1. 先停止写入并备份整个 `data` 目录。
2. 使用 Node.js 24。
3. 设置支付签名密钥和支付机构配置。
4. 执行：

```bash
node server/tools/migrate-payment-database.js /opt/chris/app/data
```

5. 确认报告中的 `ok=true`、差异为 0、账本合计为 0。
6. 启动服务，确认 `/api/payment/status` 返回 `realMoneyReady=true`。
7. 关闭旧进程前检查：

```text
GET /api/ops/payments/reconcile
GET /api/ops/payments/settlement?date=<昨日>
```

8. 完成机构沙箱、重复回调、断网重试、进程崩溃恢复和回滚演练后才可接真钱。

`realMoneyReady=true` 必须同时满足：`enforce` 模式、SQLite 支付数据库自检
通过、支付密钥就绪、持牌机构配置通过、HTTPS 机构地址、AML 引擎健康。
任何一项不满足，充值、提现和机构资金入口都会故障关闭。

运行过程中出现以下任一状态也会立即取消真钱就绪：账本哈希链异常、支付意图
链异常、dead outbox、未结对账差异或未结支付争议。清零并由人工处理后才会
重新通过 readiness。

## 测试

```bash
node server/test/payment-database.test.js
node server/test/payment-database-concurrency.test.js
node server/test/payment-real-chain.test.js
node server/test/payment-provider-server.test.js
node server/test/payment-ledger.test.js
node server/test/payment-intent.test.js
node server/test/payment-intent-ledger.test.js
```
