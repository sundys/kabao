<div align="center">

# 卡包（Card Pack）

本地加密银行卡及证件信息管理 Android 应用。所有业务数据仅以加密形式保存在用户设备本地，不连接业务服务器，不上传任何分析数据。

[![Package](https://img.shields.io/badge/package-com.sundys.kabao-1E6F5C?style=flat-square&logo=android&logoColor=white)](https://github.com/sundys/kabao/blob/master/android/app/build.gradle.kts)
[![GitHub](https://img.shields.io/badge/GitHub-sundys%2Fkabao-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/sundys/kabao)
[![Latest Release](https://img.shields.io/github/v/release/sundys/kabao?style=flat-square&label=release&logo=github&color=1E6F5C)](https://github.com/sundys/kabao/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A5%203.44-02569B?style=flat-square&logo=flutter&logoColor=white)](https://docs.flutter.dev/release/archive)
[![Dart](https://img.shields.io/badge/Dart-%E2%89%A5%203.12-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev/get-dart/archive)
[![Android SDK](https://img.shields.io/badge/Android%20SDK-36%2B-3DDC84?style=flat-square&logo=android&logoColor=white)](https://developer.android.com/studio/releases/platforms)
[![JDK](https://img.shields.io/badge/JDK-17-ED8B00?style=flat-square&logo=openjdk&logoColor=white)](https://adoptium.net/temurin/releases/?version=17)

</div>

---

## 功能介绍

### 安全与加密
- 首次启动设置主密码，主密码经 **Argon2id**（独立随机盐）派生密钥，数据使用 **AES-256-GCM** 认证加密
- 业务数据整体加密落库，数据库明文列仅保留 UUID/时间戳等非敏感元数据；未认证状态下拒绝一切读写
- 生物识别（指纹）解锁：Keystore 保护的密钥副本 + 主密码双通道，开启指纹需先验证主密码
- 修改主密码采用安全重封装流程，失败不影响原密码继续使用
- 清空全部数据需双重确认，删除业务数据、数据库文件与全部密钥材料
- 仅申请必要权限：通知（Android 13+）、生物识别、联网（只在用户手动检测更新时访问 GitHub）、安装未知应用（安装已下载的更新包）；文件读写走系统选择器，不申请宽泛存储权限

### 卡包
- 借记卡 / 信用卡 / 证件卡三个标签页，银行分类两列卡片式排版（每分类独立浅色区分）
- 银行卡字段：姓名、卡号（自动 4 位分组）、有效期（`MM/YY` 自动补 `/`）、CVV（3 位数字）、U 盾证书到期日、备注
- 证件卡字段：姓名、证件号（连续输入自动按 6/8/尾号分组显示，如 `402356 20120226 3038`）、签发机关、有效期限（连续输入数字自动补 `.` 和 `-`，可勾选「长期有效」免填日期）、备注
- 列表脱敏显示（`6222 **** **** 5678`），详情页支持复制卡号/证件号（复制为无空格纯数字）

### 通知提醒
- 本地持久化通知中心：已读、删除、长按菜单，通知加密存储
- 银行卡有效期：到期前 **90 / 60 / 30 天**及**到期当天**各提醒一次，标题区分「借记卡到期提醒」「信用卡到期提醒」
- U 盾证书到期日：到期前 **90 / 60 / 30 / 15 天**提醒
- 证件有效期限：到期前 **90 / 60 / 30 天**提醒；标记为「长期有效」的证件不产生到期提醒
- Android 通知栏使用**本地通知**，不经过服务器或推送服务；未来提醒在对应日期上午 09:00 以非精确方式调度，系统省电策略可能带来少量延迟
- 通知栏及锁屏预览只显示通用到期提示，不包含卡号、证件号、银行名称或具体到期日期；完整内容仅在已解锁的应用内加密通知中心显示
- 提醒在应用启动、回前台、数据变更时幂等重算，绝不重复；系统通知权限被拒时应用内通知中心仍完整可用

### 备份与恢复
- 导出/导入独立加密的 `.kabao` 备份文件（格式见 [docs/backup-format.md](docs/backup-format.md)）
- WebDAV 云备份：测试连接、手动备份、从云端恢复、可选的每日自动备份（显式开关）
- 备份密码独立于主密码，数据在设备上加密完成后才离开本机

### XLS 转 CSV 工具

项目提供 `tools/xls_to_kabao_csv.py`，可将 Excel 97-2003 的 `.xls` 模板转换为
卡包可导入的 UTF-8 with BOM CSV。工具只读取本地文件，不联网，也不会在终端打印卡号、
证件号、CVV 或备注。

先安装依赖：

```powershell
python -m pip install -r tools/requirements.txt
```

转换银行卡：

```powershell
python tools/xls_to_kabao_csv.py 银行卡.xls 银行卡.csv --kind cards
```

转换证件：

```powershell
python tools/xls_to_kabao_csv.py 证件.xls 证件.csv --kind documents
```

默认读取第一个工作表；指定工作表时增加 `--sheet 工作表名称`。输入文件第一行应使用
项目模板中的中文字段，也兼容旧英文字段。字段后的“（可选）”仅用于说明，转换时会自动
识别。可选的记录 ID、分类 ID、创建时间和更新时间留空后，由卡包导入时生成或按默认值处理。

模板文件：

- [银行卡模板](templates/kabao-cards-template.csv)
- [证件模板](templates/kabao-documents-template.csv)
- [银行卡 Excel 2003 模板](templates/kabao-cards-template.xls)
- [证件 Excel 2003 模板](templates/kabao-documents-template.xls)

重要：卡号和证件号在 Excel 中必须设置为“文本”格式（或在数字前加英文单引号）。如果
Excel 已将 16 位以上数字保存为普通数字，可能发生精度丢失；转换工具会拒绝这类数字单元格，
避免输出错误数据。转换后的 CSV 仍需在卡包内完成全量校验，校验失败时不会写入数据库。

更多字段规则见 [docs/xls-to-csv.md](docs/xls-to-csv.md) 和 [docs/csv-import.md](docs/csv-import.md)。

### 应用内更新
- 设置 → 关于卡包 → **检测更新**：手动检查 GitHub Releases 的最新版本，不自动检测
- 发现新版本时弹出更新窗口，展示版本号与更新说明，可选择「立即更新」
- 下载过程显示进度与速度；下载完成后自动调用系统安装器安装，更新窗口保持打开
- 安装前检查「安装未知应用」权限，未授权时跳转系统设置申请，返回后自动继续安装
- 安装被取消或失败时，返回更新窗口点「重新安装」即可复用已下载的安装包，不会重新下载；安装成功时本进程被系统结束，安装包在下次启动时回收
- 更新包放在应用私有缓存目录，且**始终最多保留一个**：每次检测更新、每次开始下载都会清掉历史版本与中断的半成品；应用启动时还会回收「当前版本已不低于缓存包版本」的安装包，不会随版本累积占用空间
- GitHub 在国内常被直连阻断，检测与下载都会依次尝试直连和若干常用加速前缀（`AppConfig.githubProxies`）；检测更新只读取公开的 Release 信息，不上传任何本地数据

### 其他
- 主题颜色设置：浅色 / 暗色 / 跟随系统
- 自动锁定超时可自定义：立即 / 30 秒 / 1 分钟 / 2 分钟 / 5 分钟 / 10 分钟（默认 30 秒），超时前返回应用无需重复验证
- 复制的卡号在应用退到后台时尽力清除

## 开发与构建

本地开发环境、编译打包、测试、发布流程、目录结构与已知问题见
[docs/dev.md](docs/dev.md)。

## 许可证

本项目采用 **CC BY-NC-ND 4.0**（署名—非商业性使用—禁止演绎）协议发布。

- ✅ 可自由复制、分发本应用及源码
- ✅ 必须注明原作者与项目地址
- ❌ 不得用于商业目的
- ❌ 不得修改后再分发（禁止演绎）

完整协议文本见 <https://creativecommons.org/licenses/by-nc-nd/4.0/legalcode>。
