# 卡包（Card Pack）

本地加密银行卡及证件信息管理 Android 应用。所有业务数据仅以加密形式保存在用户设备本地，不连接业务服务器，不上传任何分析数据。

- 应用包名：`com.sundys.kabao`
- 开源主页：<https://github.com/sundys/kabao>
- 最新版本下载：<https://github.com/sundys/kabao/releases/latest>

## 功能介绍

### 安全与加密
- 首次启动设置主密码，主密码经 **Argon2id**（独立随机盐）派生密钥，数据使用 **AES-256-GCM** 认证加密
- 业务数据整体加密落库，数据库明文列仅保留 UUID/时间戳等非敏感元数据；未认证状态下拒绝一切读写
- 生物识别（指纹）解锁：Keystore 保护的密钥副本 + 主密码双通道，开启指纹需先验证主密码
- 修改主密码采用安全重封装流程，失败不影响原密码继续使用
- 清空全部数据需双重确认，删除业务数据、数据库文件与全部密钥材料

### 卡包
- 借记卡 / 信用卡 / 证件卡三个标签页，银行分类两列卡片式排版（每分类独立浅色区分）
- 银行卡字段：姓名、卡号（自动 4 位分组）、有效期（`MM/YY` 自动补 `/`）、CVV、U 盾证书到期日、备注
- 证件卡字段：姓名、证件号、签发机关、有效期限（连续输入数字自动补 `.` 和 `-`）、备注
- 列表脱敏显示（`6222 **** **** 5678`），详情页支持复制卡号/证件号（复制为无空格纯数字）

### 通知提醒
- 本地持久化通知中心：已读、删除、长按菜单，通知加密存储
- 银行卡有效期：到期前 **90 / 60 / 30 天**及**到期当天**各提醒一次，标题区分「借记卡到期提醒」「信用卡到期提醒」
- U 盾证书到期日：到期前 **90 / 60 / 30 / 15 天**提醒
- 证件有效期限：到期前 **90 / 60 / 30 天**提醒
- 提醒在应用启动、回前台、数据变更时幂等重算，绝不重复；系统通知权限被拒时应用内通知中心仍完整可用

### 备份与恢复
- 导出/导入独立加密的 `.kabao` 备份文件（格式见 [docs/backup-format.md](docs/backup-format.md)）
- WebDAV 云备份：测试连接、手动备份、从云端恢复、可选的每日自动备份（显式开关）
- 备份密码独立于主密码，数据在设备上加密完成后才离开本机

### 其他
- 主题颜色设置：浅色 / 暗色 / 跟随系统
- 界面被覆盖 10 秒后才锁定，期间返回无需重复验证
- 复制的卡号在应用退到后台时尽力清除
- 手动检查更新（GitHub Releases），不自动检测

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

Release 工作流会按 **arm64-v8a / armeabi-v7a / x86_64** 三种架构分别构建签名 APK，并附带通用 AAB。

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
storeFile=<jks 绝对路径>
storePassword=<库密码>
keyAlias=<别名>
keyPassword=<key 密码>
```

未提供该文件时 release 构建自动降级为 debug 签名（仅供本地运行）。

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

实测体积：arm64 ≈ 19 MB、armv7 ≈ 16 MB、x86_64 ≈ 21 MB（未优化前合包 52 MB）。
`build/symbols` 中的符号文件请妥善保存，用于还原混淆后的崩溃堆栈。

## 许可证

本项目采用 **CC BY-NC-ND 4.0**（署名—非商业性使用—禁止演绎）协议发布。

- ✅ 可自由复制、分发本应用及源码
- ✅ 必须注明原作者与项目地址
- ❌ 不得用于商业目的
- ❌ 不得修改后再分发（禁止演绎）

完整协议文本见 <https://creativecommons.org/licenses/by-nc-nd/4.0/legalcode>。
