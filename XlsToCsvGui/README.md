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

CI 推送到 `xls2csv-gui` 分支或打 `v*` 标签时自动编译 win-x64 / win-x86 并发布 Release。

## 运行测试

```bash
go test ./convert
```
