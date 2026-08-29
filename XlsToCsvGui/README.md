# XlsToCsvGui - EXCEL文档转CSV UTF-8 BOM工具

将 `.xls / .xlsx / .xlsm` 转换为 **UTF-8 带 BOM** 编码的 CSV（Excel 直接打开不乱码），供 kabao 导入使用。

## 使用

双击 `xls2csv-gui.exe`：

1. **📂 打开文件** - 选择一个或多个 Excel 文件
2. 勾选 **转换所有工作表**（可选，默认只转第一个）
3. **🚀 开始转换** - 输出的 CSV 与源文件同目录同名；转换所有工作表时为 `文件名_工作表名.csv`

## 特性

- 单文件免安装，无需任何运行时（约 8MB）
- 每行自动补齐到表头列数，保证 CSV 行列数一致
- 含逗号/引号/换行的字段按 CSV 规范转义
- 文本日期原样输出（如 `03/29`），不会被改写

## 从源码编译

```bash
go build -trimpath -ldflags "-s -w -H windowsgui" -o xls2csv-gui.exe .
```

图标/manifest 已预生成为 `rsrc_windows_amd64.syso`；修改 `app.ico` 或 `app.manifest` 后需重新生成：

```bash
go run github.com/akavel/rsrc@latest -manifest app.manifest -ico app.ico -arch amd64 -o rsrc_windows_amd64.syso
```

CI 推送到 `xls2csv-gui` 分支时自动编译 win-x64 / win-x86（结果见 Actions 页面）；推 `gui-v*` 标签时额外发布 GitHub Release。

## 发布新版

1. 确认代码已推送到 `xls2csv-gui` 分支：

   ```bash
   git push
   ```

2. 打标签并推送，触发自动编译发布：

   ```bash
   git tag gui-v1.0.1 -m "版本说明"
   git push origin gui-v1.0.1
   ```

3. 约 3~5 分钟后，在 [Releases](https://github.com/sundys/kabao/releases) 页面即可看到带 `xls2csv-gui-win-x64.exe` 和 `xls2csv-gui-win-x86.exe` 的新版本。

注意事项：

- 标签必须以 `gui-v` 开头（如 `gui-v1.0.1`）。纯 `v*` 标签会误触发主应用的 Flutter 发布流程，已被禁止。
- 发布需 `permissions: contents: write`，工作流中已配置，请勿删除。
- 同一版本号重新发布：先删标签再重打即可，`release` 任务会重建对应 Release：

  ```bash
  git push origin :refs/tags/gui-v1.0.1   # 删除远程标签
  git tag -d gui-v1.0.1
  # 修改代码提交后:
  git tag gui-v1.0.1 -m "版本说明" && git push origin gui-v1.0.1
  ```

## 运行测试

```bash
go test ./convert
```
