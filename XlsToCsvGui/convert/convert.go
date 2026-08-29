// Package convert 提供 xls/xlsx -> UTF-8 BOM CSV 的转换核心, 供 GUI 和测试调用。
package convert

import (
	"archive/zip"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/shakinm/xlsReader/xls"
	"github.com/xuri/excelize/v2"
)

// LogFn 用于向 GUI 日志窗口输出进度信息
type LogFn func(format string, a ...any)

// File 转换一个 Excel 文件。allSheets=true 时每个工作表各生成一个 CSV。
// 返回生成的 CSV 文件路径列表。
func File(path string, allSheets bool, log LogFn) ([]string, error) {
	if log == nil {
		log = func(string, ...any) {}
	}
	if _, err := os.Stat(path); err != nil {
		return nil, fmt.Errorf("文件不存在: %s", path)
	}
	ext := strings.ToLower(filepath.Ext(path))
	if ext != ".xls" && ext != ".xlsx" && ext != ".xlsm" {
		return nil, fmt.Errorf("不支持的文件类型: %s (仅支持 .xls/.xlsx/.xlsm)", ext)
	}

	var sheets []sheetData
	var err error
	if ext == ".xls" {
		sheets, err = readXLS(path)
	} else {
		sheets, err = readXLSX(path)
	}
	if err != nil {
		return nil, err
	}

	base := strings.TrimSuffix(path, filepath.Ext(path))
	var outs []string
	for i, sh := range sheets {
		if !allSheets && i > 0 {
			break
		}
		padRows(sh.rows)
		out := base + ".csv"
		if allSheets || len(sheets) > 1 {
			out = fmt.Sprintf("%s_%s.csv", base, sanitizeName(sh.name))
		}
		if err := writeCSV(out, sh.rows); err != nil {
			return outs, fmt.Errorf("写入 %s 失败: %v", out, err)
		}
		log("[成功] %s [%s] -> %s (%d 行)", filepath.Base(path), sh.name, out, len(sh.rows))
		outs = append(outs, out)
	}
	if len(outs) == 0 {
		return nil, fmt.Errorf("未找到任何工作表")
	}
	return outs, nil
}

type sheetData struct {
	name string
	rows [][]string
}

// padRows 把表内所有行补齐到同一列数。
// xls/xlsx 读取器会丢掉行尾的空单元格, 导致各行列数不一,
// 而 CSV 导入工具通常要求每行列数与表头一致。
func padRows(rows [][]string) {
	max := 0
	for _, r := range rows {
		if len(r) > max {
			max = len(r)
		}
	}
	for i := range rows {
		for len(rows[i]) < max {
			rows[i] = append(rows[i], "")
		}
	}
}

func sanitizeName(s string) string {
	s = strings.Map(func(r rune) rune {
		switch r {
		case '\\', '/', ':', '*', '?', '"', '<', '>', '|':
			return '_'
		}
		return r
	}, s)
	if s == "" {
		return "Sheet"
	}
	return s
}

// writeCSV 以 UTF-8 带 BOM 写出, 含分隔符/引号/换行的字段按 CSV 规范加引号转义
func writeCSV(path string, rows [][]string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.Write([]byte{0xEF, 0xBB, 0xBF}); err != nil { // UTF-8 BOM
		return err
	}
	var sb strings.Builder
	for _, row := range rows {
		sb.Reset()
		for i, cell := range row {
			if i > 0 {
				sb.WriteByte(',')
			}
			if strings.ContainsAny(cell, ",\"\n\r") {
				sb.WriteByte('"')
				sb.WriteString(strings.ReplaceAll(cell, "\"", "\"\""))
				sb.WriteByte('"')
			} else {
				sb.WriteString(cell)
			}
		}
		sb.WriteString("\r\n")
		if _, err := f.WriteString(sb.String()); err != nil {
			return err
		}
	}
	return nil
}

// readXLSX 用 excelize 读取 xlsx/xlsm, GetRows 返回的是按单元格格式化后的文本
func readXLSX(path string) ([]sheetData, error) {
	f, err := excelize.OpenFile(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []sheetData
	for _, name := range f.GetSheetList() {
		rows, err := f.GetRows(name)
		if err != nil {
			return nil, fmt.Errorf("读取工作表 %s 失败: %v", name, err)
		}
		out = append(out, sheetData{name: name, rows: rows})
	}
	return out, nil
}

// readXLS 用 shakinm/xlsReader 读取旧版二进制 xls
func readXLS(path string) ([]sheetData, error) {
	wb, err := xls.OpenFile(path)
	if err != nil {
		return nil, err
	}
	var out []sheetData
	for i := 0; i < wb.GetNumberSheets(); i++ {
		sh, err := wb.GetSheet(i)
		if err != nil {
			return nil, err
		}
		rows := sh.GetRows()
		data := make([][]string, 0, len(rows))
		for _, r := range rows {
			cols := r.GetCols()
			row := make([]string, len(cols))
			for ci, c := range cols {
				row[ci] = c.GetString()
			}
			data = append(data, row)
		}
		out = append(out, sheetData{name: sh.GetName(), rows: data})
	}
	return out, nil
}

// IsZipFile 检测文件是否为 zip 容器, 用于给用户区分 xls/xlsx 内容损坏的情况
func IsZipFile(path string) bool {
	f, err := zip.OpenReader(path)
	if err != nil {
		return false
	}
	f.Close()
	return true
}
