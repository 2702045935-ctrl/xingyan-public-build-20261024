# 银行级审计中心

## 目标

审计中心不是普通后台的第二个皮肤，而是独立证据读取入口。目标是让一次高敏操作能够同时回答：

- 谁发起了操作；
- 哪个请求号触发；
- 操作前后动用了什么资金或权限；
- 是否经过二次确认或双人复核；
- 证据链是否完整；
- 导出的证据包能否验证未被改动。

## 主链

运营审计主链文件：

```text
data/audit-bank.jsonl
data/audit-bank-state.json
```

每条记录包含：

```json
{
  "schema": "xingyan.banking.audit.v1",
  "seq": 1,
  "requestId": "req_...",
  "actor": {"id": "...", "username": "...", "name": "...", "role": "..."},
  "source": {"ip": "...", "userAgent": "..."},
  "category": "finance",
  "severity": "attention",
  "outcome": "success",
  "action": "...",
  "target": "...",
  "detail": "...",
  "context": {},
  "prevHash": "",
  "hash": "..."
}
```

写入顺序固定为：

1. 获取跨进程锁；
2. 读取/恢复链状态；
3. 生成 `seq`、`prevHash` 和 HMAC-SHA256；
4. 使用 AES-256-GCM 加密记录后追加写并 `fsync`；
5. 原子写入状态文件；
6. 释放锁。

审计链写入失败会抛错，业务接口不能静默返回成功。旧 `audit.log` 仅用于兼容历史页面。

## 请求关联

HTTP 入口生成或接收 `X-Request-ID`，响应头回传同一个值，并写入主链。敏感操作、请求日志和证据包可以使用同一请求号定位。

## 金融结构化上下文

以下动作除文本 detail 外，会写入 `context`：

- 支付账本对账；
- 支付争议登记、结案、核销；
- 支付对账差异结案；
- 撤销交易；
- 支付风控冻结/解冻；
- 提现完成/失败；
- 后台余额充值/扣减。

结构化上下文包含 `kind`、金额、币种、用户/交易/争议 ID、原因、流水号或复核信息。

## 完整性校验

```text
GET /api/ops/audit/integrity
```

同时校验：

- 运营 HMAC 链的序号、前序哈希和 HMAC；
- AML 加密证据链；
- 支付账本 HMAC 链；
- 当前资金余额与账本对账结果。

校验动作本身也写入运营主链。

## 签名导出

```text
GET /api/ops/audit/export
```

服务端返回事件、首尾序号、链尾哈希和 `manifestMac`。客户端只负责保存服务端证据包，不自行计算或补造签名。

## 访问控制

- 审计链读取：`audit`；
- 金融与完整性读取：`audit + payments`；
- 审计中心不提供删除、修改、补录接口；
- 资金处置仍需在受控后台执行，并经过二次密码确认和可用的双人复核。
