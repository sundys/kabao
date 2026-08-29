#!/usr/bin/env python3
"""Convert a Kabao-compatible .xls workbook to a UTF-8 BOM CSV file.

The converter is intentionally offline. It reads the first worksheet by
default, maps Chinese/English template headers, normalizes common Excel date
and boolean representations, and writes UTF-8 with BOM for Excel 2003.
Sensitive cell values are never printed.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import math
import re
import sys
from pathlib import Path
from typing import Any

try:
    import xlrd  # type: ignore
except ImportError as exc:  # pragma: no cover - exercised by CLI users
    raise SystemExit(
        "缺少依赖 xlrd，请先执行：python -m pip install xlrd==2.0.1"
    ) from exc


CARD_HEADERS = [
    "记录类型（可选）", "分类类型", "分类名称", "分类ID（可选）",
    "记录ID（可选）", "持有人姓名（可选）", "卡号", "有效期（可选）",
    "CVV（可选）", "U盾到期日（可选）", "备注（可选）", "创建时间（可选）",
    "更新时间（可选）",
]
DOCUMENT_HEADERS = [
    "记录类型（可选）", "分类类型", "分类名称", "分类ID（可选）",
    "记录ID（可选）", "持有人姓名（可选）", "证件号", "签发机关",
    "有效期起（非长期有效必填）", "有效期止（非长期有效必填）",
    "长期有效（可选）", "备注（可选）", "创建时间（可选）", "更新时间（可选）",
]

ALIASES = {
    "记录类型": "record_type", "record_type": "record_type",
    "分类类型": "category_type", "category_type": "category_type",
    "分类名称": "category_name", "category_name": "category_name",
    "分类ID": "category_id", "category_id": "category_id",
    "记录ID": "id", "id": "id",
    "持有人姓名": "holder_name", "holder_name": "holder_name", "姓名": "holder_name",
    "卡号": "card_number", "card_number": "card_number",
    "有效期": "expiry", "expiry": "expiry",
    "CVV": "cvv", "cvv": "cvv",
    "U盾到期日": "u_shield_expiry", "u_shield_expiry": "u_shield_expiry",
    "备注": "note", "note": "note", "remark": "remark",
    "证件号": "id_number", "id_number": "id_number",
    "签发机关": "issuer", "issuer": "issuer",
    "有效期起": "valid_from", "valid_from": "valid_from",
    "有效期止": "valid_to", "valid_to": "valid_to",
    "长期有效": "validity_permanent", "validity_permanent": "validity_permanent",
    "创建时间": "created_at", "created_at": "created_at",
    "更新时间": "updated_at", "updated_at": "updated_at",
}


def clean_header(value: Any) -> str:
    text = str(value or "").strip().lstrip("\ufeff")
    text = re.sub(r"\s*[（(][^（）()]*[）)]\s*$", "", text)
    return ALIASES.get(text, text)


def text_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int,)):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return ""
        if value.is_integer():
            return str(int(value))
        return format(value, "f").rstrip("0").rstrip(".")
    return str(value).strip()


def sensitive_value(value: Any, field: str, row_number: int) -> str:
    """Return an identifier while refusing lossy Excel floating-point cells."""
    if isinstance(value, float) and not math.isnan(value) and value.is_integer():
        digits = str(int(value))
        # Excel numeric cells cannot safely represent long card/ID values.
        if len(digits) >= 15:
            raise ValueError(
                f"第 {row_number} 行的 {field} 是数字单元格，可能已丢失精度；"
                "请在 Excel 中将该列设置为“文本”后重新保存"
            )
    return text_value(value)


def excel_date(book: Any, sheet: Any, row: int, col: int, value: Any) -> dt.datetime | None:
    if isinstance(value, dt.datetime):
        return value
    if isinstance(value, dt.date):
        return dt.datetime.combine(value, dt.time())
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        try:
            return xlrd.xldate_as_datetime(value, book.datemode)
        except (TypeError, ValueError, xlrd.XLDateError):
            return None
    return None


def normalize_date(value: Any, book: Any, sheet: Any, row: int, col: int, kind: str) -> str:
    raw = text_value(value)
    if not raw:
        return ""
    parsed = excel_date(book, sheet, row, col, value)
    if parsed:
        if kind == "expiry":
            return f"{parsed.month:02d}/{parsed.year % 100:02d}"
        if kind == "slash":
            return f"{parsed.year}/{parsed.month}/{parsed.day}"
        if kind == "iso":
            return parsed.isoformat(timespec="seconds")
        return f"{parsed.year:04d}.{parsed.month:02d}.{parsed.day:02d}"
    if kind == "iso":
        parsed_text = re.match(
            r"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$",
            raw,
        )
        if parsed_text:
            year, month, day = (int(parsed_text.group(i)) for i in (1, 2, 3))
            hour = int(parsed_text.group(4) or 0)
            minute = int(parsed_text.group(5) or 0)
            second = int(parsed_text.group(6) or 0)
            try:
                return dt.datetime(year, month, day, hour, minute, second).isoformat(timespec="seconds")
            except ValueError:
                pass
    return raw


def normalize_type(value: Any, document: bool = False) -> str:
    raw = text_value(value).lower()
    if document or raw in {"document", "证件", "证件卡"}:
        return "document"
    if raw in {"debit", "借记卡", "借记", "储蓄卡"}:
        return "debit"
    if raw in {"credit", "信用卡", "贷记卡"}:
        return "credit"
    return text_value(value)


def normalize_bool(value: Any) -> str:
    raw = text_value(value).lower()
    if raw in {"true", "1", "yes", "y", "是", "长期有效"}:
        return "true"
    if raw in {"false", "0", "no", "n", "否"}:
        return "false"
    return ""


def convert(input_path: Path, output_path: Path, kind: str, sheet_name: str | None) -> int:
    book = xlrd.open_workbook(str(input_path), formatting_info=False)
    try:
        sheet = book.sheet_by_name(sheet_name) if sheet_name else book.sheet_by_index(0)
    except (IndexError, xlrd.biffh.XLRDError) as exc:
        raise ValueError("找不到指定工作表") from exc
    if sheet.nrows < 1:
        raise ValueError("工作表为空")

    headers = [clean_header(sheet.cell_value(0, col)) for col in range(sheet.ncols)]
    if len(headers) != len(set(headers)) or any(not h for h in headers):
        raise ValueError("表头为空或重复")
    required = {"category_name", "category_type", "card_number"} if kind == "cards" else {"category_name", "id_number", "issuer"}
    missing = sorted(required - set(headers))
    if missing:
        raise ValueError("缺少必要列：" + ", ".join(missing))

    output_headers = CARD_HEADERS if kind == "cards" else DOCUMENT_HEADERS
    canonical = {h: i for i, h in enumerate(headers)}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with output_path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=output_headers, lineterminator="\n")
        writer.writeheader()
        for row_idx in range(1, sheet.nrows):
            if all(not text_value(sheet.cell_value(row_idx, col)) for col in range(sheet.ncols)):
                continue
            source = {h: sheet.cell_value(row_idx, col) for h, col in canonical.items()}
            out = {h: "" for h in output_headers}
            out["记录类型（可选）"] = "card" if kind == "cards" else "document"
            out["分类类型"] = normalize_type(source.get("category_type"), kind == "documents")
            out["分类名称"] = text_value(source.get("category_name"))
            out["分类ID（可选）"] = text_value(source.get("category_id"))
            out["记录ID（可选）"] = text_value(source.get("id"))
            out["持有人姓名（可选）"] = text_value(source.get("holder_name"))
            out["创建时间（可选）"] = normalize_date(source.get("created_at"), book, sheet, row_idx, canonical.get("created_at", -1), "iso")
            out["更新时间（可选）"] = normalize_date(source.get("updated_at"), book, sheet, row_idx, canonical.get("updated_at", -1), "iso")
            if kind == "cards":
                out["卡号"] = sensitive_value(source.get("card_number"), "卡号", row_idx + 1)
                out["有效期（可选）"] = normalize_date(source.get("expiry"), book, sheet, row_idx, canonical.get("expiry", -1), "expiry")
                out["CVV（可选）"] = text_value(source.get("cvv"))
                out["U盾到期日（可选）"] = normalize_date(source.get("u_shield_expiry"), book, sheet, row_idx, canonical.get("u_shield_expiry", -1), "slash")
                out["备注（可选）"] = text_value(source.get("note") or source.get("remark"))
            else:
                out["证件号"] = sensitive_value(source.get("id_number"), "证件号", row_idx + 1)
                out["签发机关"] = text_value(source.get("issuer"))
                out["有效期起（非长期有效必填）"] = normalize_date(source.get("valid_from"), book, sheet, row_idx, canonical.get("valid_from", -1), "dot")
                out["有效期止（非长期有效必填）"] = normalize_date(source.get("valid_to"), book, sheet, row_idx, canonical.get("valid_to", -1), "dot")
                out["长期有效（可选）"] = normalize_bool(source.get("validity_permanent"))
                out["备注（可选）"] = text_value(source.get("remark") or source.get("note"))
            writer.writerow(out)
            count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description="将 Kabao .xls 模板转换为 UTF-8 BOM CSV")
    parser.add_argument("input", type=Path, help="输入 .xls 文件")
    parser.add_argument("output", type=Path, help="输出 .csv 文件")
    parser.add_argument("--kind", choices=("cards", "documents"), required=True, help="cards=银行卡，documents=证件")
    parser.add_argument("--sheet", help="工作表名称，默认第一个工作表")
    args = parser.parse_args()
    if args.input.suffix.lower() != ".xls":
        print("错误：输入文件必须是 Excel 97-2003 .xls 格式", file=sys.stderr)
        return 2
    try:
        count = convert(args.input, args.output, args.kind, args.sheet)
    except (OSError, ValueError, xlrd.biffh.XLRDError) as exc:
        print(f"转换失败：{exc}", file=sys.stderr)
        return 1
    print(f"转换完成：{count} 行；输出文件已使用 UTF-8 BOM 编码。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
