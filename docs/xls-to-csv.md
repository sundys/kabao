# XLS 转 Kabao CSV 工具

`tools/xls_to_kabao_csv.py` 用于把 Excel 97-2003 的 `.xls` 模板转换为可导入卡包的 CSV。输出编码为 **UTF-8 with BOM**，可被 Excel 2003 中文版直接打开。

## 安装依赖

```powershell
python -m pip install -r tools/requirements.txt
```

## 使用

银行卡：

```powershell
python tools/xls_to_kabao_csv.py 银行卡.xls 银行卡.csv --kind cards
```

证件：

```powershell
python tools/xls_to_kabao_csv.py 证件.xls 证件.csv --kind documents
```

默认读取第一个工作表，可用 `--sheet 工作表名称` 指定工作表。输入表格第一行应为与 Kabao 模板相同的中文字段；字段后的“（可选）”会自动识别并去除。工具也兼容旧英文字段名。

工具会转换 Excel 日期序列、常见日期文本和布尔值，并输出中文模板表头。空的 ID、分类 ID、创建/更新时间等字段保持为空，由 Kabao 导入时生成或按默认值处理。转换过程不会在终端打印卡号、证件号、CVV 或备注。

卡号和证件号必须在 Excel 中设置为“文本”格式（建议在数字前加英文单引号），否则 Excel 的浮点数会导致 16 位以上数字精度丢失。工具检测到这类数字单元格时会拒绝转换，不会输出错误数据。

转换后仍需在卡包内执行全量预校验；任何错误都不会写入数据库。
