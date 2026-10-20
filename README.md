# 星言 iOS 客户端

原生 SwiftUI IM 客户端，最低支持 iOS 16。工程由 `swiftc` 直接编译，通过 GitHub Actions 生成未签名 IPA。

## 目录

- `Sources/`：Swift 源码
- `.github/workflows/build-ios.yml`：云端构建配置
- `core.lock.json`：核心运行模块校验清单
- `tools/verify-core.ps1`：Windows 核心校验脚本
- `tools/verify-core.sh`：macOS/Linux 核心校验脚本

## 本地校验

修改代码后先执行：

```powershell
pwsh -File tools/verify-core.ps1
```

macOS 或 Linux：

```bash
bash tools/verify-core.sh
```

`core.lock.json` 中的文件涉及网络、登录、消息同步、聊天主流程、音视频和本地存储。确需修改时，应完成真机回归后再更新清单，不建议直接删除校验。

## 构建

在 GitHub Actions 中手动运行 `build-ios`。构建机需要 Xcode 26、WebRTC 和腾讯 TRTC iOS SDK。产物为 AES-256 加密的未签名 IPA，解密密码只保存在仓库 Secret `IPA_PASSWORD` 中。

## 开发约束

- 聊天首屏和滚动路径改动后必须验证冷启动、键盘、返回和长会话。
- 音视频模块改动后必须验证 iOS 与鸿蒙互拨。
- 网络证书固定不可关闭。服务器证书更换时，需要同步更新 `ServerTrustPolicy`。
- 客户端不保存服务端密钥、支付密钥或第三方密钥。
