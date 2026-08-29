package convert

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConvertXlsxAndXls(t *testing.T) {
	for _, src := range []string{"../../测试数据.xlsx", "../../测试数据.xls"} {
		if _, err := os.Stat(src); err != nil {
			t.Skipf("测试文件不存在: %s", src)
		}
		outs, err := File(src, true, func(f string, a ...any) { t.Logf(f, a...) })
		if err != nil {
			t.Fatalf("%s: %v", src, err)
		}
		if len(outs) == 0 {
			t.Fatalf("%s: 没有输出文件", src)
		}
		for _, out := range outs {
			data, err := os.ReadFile(out)
			if err != nil {
				t.Fatal(err)
			}
			// 验证 BOM
			if len(data) < 3 || data[0] != 0xEF || data[1] != 0xBB || data[2] != 0xBF {
				t.Fatalf("%s: 缺少 UTF-8 BOM", out)
			}
			text := string(data[3:])
			for _, want := range []string{"姓名,年龄,备注", "张三,25,普通", "李四,30,\"含\"\"引号\"\"\"", "\"王,五\",41,\"多"} {
				if !strings.Contains(text, want) {
					t.Errorf("%s: 缺少期望内容 %q\n实际:\n%s", out, want, text)
				}
			}
			t.Logf("%s 内容验证通过", filepath.Base(out))
		}
	}
}
