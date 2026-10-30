# 开发与发布指南

本文档汇总卡包的本地开发、构建、测试、发布流程与已知问题。项目功能说明与快速上手见
[README](../README.md)。

## 编译部署

### 环境要求

| 项目 | 版本 |
| --- | --- |
| Flutter | stable ≥ 3.44 |
| Dart | ≥ 3.12 |
| Android SDK | Compile SDK 36+ |
| JDK | 17 |

### 本地开发

```powershell
flutter pub get
flutter run
```

### 质量检查（每次改动至少执行）

```powershell
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

### 集成测试（需真机或模拟器）

```powershell
flutter test integration_test/app_flow_test.dart -d <device-id>
```

### 图标更新

替换 `assets/icon/app_icon.png`（建议 1024×1024 PNG）后执行：

```powershell
dart run flutter_launcher_icons
```

## 发布与环境变量

推送 `v*` 标签触发 GitHub Actions 自动构建并发布 Release：

```powershell
git tag v1.0.1
git push origin v1.0.1
```

Release 工作流会按 **arm64-v8a / armeabi-v7a** 两种 Android 架构分别构建签名 APK，并附带通用 AAB。

### 需要配置的 GitHub Secrets

| Secret | 说明 |
| --- | --- |
| `KEYSTORE_BASE64` | 签名 keystore 文件的 Base64 编码内容 |
| `KEYSTORE_PASSWORD` | keystore 库密码 |
| `KEY_ALIAS` | 签名密钥别名 |
| `KEY_PASSWORD` | 签名密钥密码 |

### 签名文件如何生成

在本地执行（将 `<alias>`、`<keystore名>` 替换为实际值）：

```powershell
keytool -genkey -v -keystore kabao-release.jks `
  -keyalg RSA -keysize 2048 -validity 36500 `
  -alias <alias>
```

按提示设置 keystore 密码与 key 密码（两者可相同）。然后计算 Base64：

```powershell
# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("kabao-release.jks")) | Set-Content keystore-base64.txt
```

```bash
# Linux / macOS
base64 -w0 kabao-release.jks > keystore-base64.txt   # macOS 用 base64 -i kabao-release.jks
```

把 `keystore-base64.txt` 的完整内容填入 Secrets 的 `KEYSTORE_BASE64`，其余三个 Secrets 填入对应密码与别名。

> ⚠️ `kabao-release.jks` 与 `android/key.properties` 已加入 `.gitignore`，
> **绝不能提交到仓库**；丢失 keystore 将无法再发布同签名的升级包。

本地签名调试：创建 `android/key.properties`（同样不提交）：

```properties
# 绝对路径，或相对 android/ 的路径（如 keystore/local-test.jks）
storeFile=<jks 路径>
storePassword=<库密码>
keyAlias=<别名>
keyPassword=<key 密码>
# 可选：标记为本地测试签名，版本名会追加 -local
localTest=true
```

未提供该文件时 release 构建自动降级为 debug 签名（仅供本地运行）。

> 仓库内 `android/keystore/local-test.jks` 是**本地测试密钥**（口令与别名均为
> `kabao-local-test`），只用于本机出包自测。它签出的包无法覆盖安装正式包，
> 正式发布包始终由 GitHub Actions 用 Secrets 中的真实 keystore 构建。

## 目录结构

```text
lib/
  app/                 # App 根组件、路由、主题、依赖装配
  core/                # 加密服务、密钥管理、加密数据库、平台服务
  features/
    auth/              # 主密码设置、锁定状态、生物识别
    wallet/            # 分类、银行卡/证件卡 CRUD、录入校验、脱敏
    notifications/     # 到期规则计算、通知持久化、通知中心
    backup/            # 备份编解码、导入导出、WebDAV
    settings/          # 设置、修改密码、清空数据、关于
  shared/              # 校验工具、格式化、输入格式化器等
tools/                 # XLS 转 UTF-8 BOM CSV 工具
test/                  # 单元测试与 Widget 测试
integration_test/      # 集成测试（真机/模拟器）
.github/workflows/     # CI 与 Release 工作流
docs/backup-format.md  # 备份格式规范
```

## 减小体积与提升运行速度

- **始终使用 Release 模式分发**：Debug 包含 JIT 内核与调试符号，体积数倍于 Release 且运行慢（AOT）
- **按架构分包**：`--split-per-abi` 后单架构包约为全架构合包的 1/3
- 项目已启用的优化：R8 混淆（`minifyEnabled`）、资源收缩（`shrinkResources`）、图标字体树摇、Dart 符号混淆剥离（`--obfuscate --split-debug-info`）
- 本地构建优化版 APK：

```powershell
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```

实测体积：arm64 ≈ 19 MB、armv7 ≈ 16 MB（未优化前合包 52 MB）。
`build/symbols` 中的符号文件请妥善保存，用于还原混淆后的崩溃堆栈。

## 已知问题

- **构建日志中的 KGP 警告**：`file_picker 10.x` 尚未迁移到 Flutter 的 Built-in Kotlin，
  构建时会输出 KGP 警告。该警告**目前不影响构建与运行**，仅表示未来 Flutter 大版本
  可能不再兼容。彻底消除需升级 `file_picker ≥ 12`，但其依赖链（win32 6.x）与本项目
  的 `flutter_secure_storage 9.x` 冲突，且 `file_picker 11/12` 需要更高的 AGP 与
  Compile SDK 37。待 `flutter_secure_storage` 升级到 10+ 并提升 AGP 后一并处理。
