package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/lxn/walk"
	. "github.com/lxn/walk/declarative"
	"github.com/lxn/win"
	"xlstocsv/convert"
)

//go:embed app.ico
var icoBytes []byte

// loadAppIcon 加载应用图标, 不依赖 exe 外部文件。
// ico 内容通过 go:embed 打进 exe, 加载时写到临时文件再读取
// (walk 的 exe 资源图标 API 在部分系统上不可用);
// 都失败时返回 nil, 由调用方跳过图标设置 (传 nil 图标会导致 walk panic)。
func loadAppIcon() *walk.Icon {
	if len(icoBytes) > 0 {
		if f, err := os.CreateTemp("", "xls2csv-*.ico"); err == nil {
			if _, err := f.Write(icoBytes); err == nil {
				f.Close()
				if ic, err := walk.NewIconFromFile(f.Name()); err == nil {
					os.Remove(f.Name())
					return ic
				}
			}
			f.Close()
		}
	}
	if ic, err := walk.NewIconFromFile("app.ico"); err == nil {
		return ic
	}
	return nil
}

var (
	// 现代浅色主题配色
	bgWindow = walk.RGB(0xF5, 0xF6, 0xF8) // 主背景 浅灰蓝
	bgCard   = walk.RGB(0xFF, 0xFF, 0xFF) // 卡片白
	bgDark   = walk.RGB(0x1E, 0x20, 0x30) // 日志区 深蓝黑
	fgDark   = walk.RGB(0xE6, 0xE9, 0xF0) // 日志文字 亮灰
	fgSub    = walk.RGB(0x6B, 0x72, 0x80) // 次要文字 灰
)

var (
	mw      *walk.MainWindow
	logEdit *walk.TextEdit
	fileEdt *walk.LineEdit
	convBtn *walk.PushButton
	allCB   *walk.CheckBox

	mu       sync.Mutex
	files    []string
	running  bool
)

func main() {
	decl := MainWindow{
		AssignTo: &mw,
		Title:    "EXCEL文档转CSV UTF-8 BOM工具",
		MinSize:  Size{Width: 660, Height: 460},
		Size:     Size{Width: 760, Height: 540},
		Layout:   VBox{Margins: Margins{Left: 18, Top: 16, Right: 18, Bottom: 16}, Spacing: 12},
		Background: SolidColorBrush{Color: walk.RGB(0xF5, 0xF6, 0xF8)},
		Font:     Font{Family: "Microsoft YaHei UI", PointSize: 9},
		Children: []Widget{
			// 顶部标题卡片
			Composite{
				DoubleBuffering: true,
				Layout: VBox{Margins: Margins{Left: 16, Top: 12, Right: 16, Bottom: 12}, Spacing: 4},
				Background: SolidColorBrush{Color: bgCard},
				Children: []Widget{
					Label{
						Text: "EXCEL 文档转 CSV 工具",
						Font: Font{Family: "Microsoft YaHei UI", PointSize: 14, Bold: true},
					},
					Label{
						Text:       "支持 .xls / .xlsx / .xlsm，输出 UTF-8 带 BOM 编码的 CSV，Excel 打开不乱码",
						TextColor:  fgSub,
					},
				},
			},
			// 文件选择行
			Composite{
				DoubleBuffering: true,
				Layout: HBox{MarginsZero: true, Spacing: 10},
				Children: []Widget{
					PushButton{
						Text:    "📂 打开文件",
						MinSize: Size{Width: 110, Height: 34},
						OnClicked: browseFiles,
					},
					LineEdit{
						AssignTo:  &fileEdt,
						ReadOnly:  true,
						CueBanner: "尚未选择文件，可一次选择多个",

					},
				},
			},
			// 操作行
			Composite{
				DoubleBuffering: true,
				Layout: HBox{MarginsZero: true, Spacing: 10},
				Children: []Widget{
					PushButton{
						AssignTo: &convBtn,
						Text:     "🚀 开始转换",
						MinSize:  Size{Width: 110, Height: 34},
						OnClicked: startConvert,
					},
					CheckBox{AssignTo: &allCB, Text: "转换所有工作表"},
					HSpacer{},
				},
			},
			// 日志区
			TextEdit{
				AssignTo:  &logEdit,
				ReadOnly:  true,
				VScroll:   true,

				MinSize:   Size{Height: 220},
				Font:      Font{Family: "Consolas", PointSize: 9},
				Background: SolidColorBrush{Color: bgDark},
				TextColor: fgDark,
				Text:      "就绪。\r\n",
			},
		},
	}
	// 图标: 设置失败不传 nil, 避免 walk 空指针崩溃
	if icon := loadAppIcon(); icon != nil {
		decl.Icon = icon
	}
	decl.Create()

	// 合成双缓冲: 让 Windows 自底向上合成整个控件树, 消除布局/重绘时的闪烁
	// (只读 Edit 控件在重绘间隙会露出系统浅色底, 即用户看到的"日志窗口变浅色")
	ex := win.GetWindowLong(mw.Handle(), win.GWL_EXSTYLE)
	win.SetWindowLong(mw.Handle(), win.GWL_EXSTYLE, ex|win.WS_EX_COMPOSITED)

	mw.Run()
}

func appendLog(s string) {
	logEdit.AppendText(s + "\r\n")
}

func browseFiles() {
	dlg := walk.FileDialog{
		Title:  "选择 Excel 文件",
		Filter: "Excel 文件 (*.xls;*.xlsx;*.xlsm)|*.xls;*.xlsx;*.xlsm|所有文件 (*.*)|*.*",
	}
	ok, err := dlg.ShowOpenMultiple(mw)
	if err != nil || !ok {
		return
	}
	mu.Lock()
	files = dlg.FilePaths
	mu.Unlock()
	fileEdt.SetText(displayFiles(dlg.FilePaths))
}

func displayFiles(paths []string) string {
	if len(paths) == 1 {
		return paths[0]
	}
	return fmt.Sprintf("已选择 %d 个文件: %s 等", len(paths), filepath.Base(paths[0]))
}

func startConvert() {
	mu.Lock()
	if running {
		mu.Unlock()
		return
	}
	todo := append([]string(nil), files...)
	running = true
	all := allCB.Checked()
	mu.Unlock()

	if len(todo) == 0 {
		walk.MsgBox(mw, "提示", "请先点击「打开文件」选择要转换的 Excel 文件。", walk.MsgBoxIconInformation)
		running = false
		return
	}

	convBtn.SetEnabled(false)
	appendLog("――――――――――――――――――――")
	appendLog(fmt.Sprintf("开始转换 %d 个文件...", len(todo)))

	go func() {
		okCount, failCount := 0, 0
		for _, f := range todo {
			if _, err := convert.File(f, all, func(format string, a ...any) {
				msg := fmt.Sprintf(format, a...)
				mw.Synchronize(func() { appendLog(msg) })
			}); err != nil {
				mw.Synchronize(func() {
					appendLog("[错误] " + f + ": " + err.Error())
					failCount++
				})
			} else {
				mw.Synchronize(func() { okCount++ })
			}
		}
		mw.Synchronize(func() {
			appendLog(fmt.Sprintf("完成: 成功 %d 个文件, 失败 %d 个。", okCount, failCount))
			convBtn.SetEnabled(true)
			if failCount == 0 {
				walk.MsgBox(mw, "转换完成",
					fmt.Sprintf("成功转换 %d 个文件！\n输出为 UTF-8 (BOM) 编码 CSV，与源文件同目录。", okCount),
					walk.MsgBoxIconInformation)
			} else {
				walk.MsgBox(mw, "转换完成 (有错误)",
					fmt.Sprintf("成功 %d 个，失败 %d 个。\n详情见日志窗口。", okCount, failCount),
					walk.MsgBoxIconWarning)
			}
			mu.Lock()
			running = false
			mu.Unlock()
		})
	}()
}
