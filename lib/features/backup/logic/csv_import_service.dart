import 'package:uuid/uuid.dart';

import '../../../core/database/encrypted_database.dart';
import '../../../shared/utils/card_number_utils.dart';
import '../../../shared/utils/document_id_utils.dart';
import '../../../shared/validation/validators.dart';
import '../../wallet/domain/document.dart';
import '../../wallet/domain/models.dart';
import 'backup_codec.dart';
import 'backup_service.dart';

enum CsvImportKind { cards, documents }

final class CsvImportError {
  const CsvImportError({
    required this.row,
    required this.field,
    required this.message,
  });

  final int row;
  final String field;
  final String message;
}

final class CsvImportDraft {
  const CsvImportDraft({
    required this.kind,
    required this.snapshot,
    required this.totalRows,
    required this.errors,
    required this.createdCategoryCount,
  });

  final CsvImportKind kind;
  final VaultSnapshot snapshot;
  final int totalRows;
  final List<CsvImportError> errors;
  final int createdCategoryCount;

  bool get isValid => errors.isEmpty && totalRows > 0;
  int get recordCount => kind == CsvImportKind.cards
      ? snapshot.cards.length
      : snapshot.documents.length;
}

final class CsvImportService {
  CsvImportService({required this.categories, required this.database});

  final List<BankCategory> categories;
  final EncryptedDatabase database;

  CsvImportDraft prepare({
    required String contents,
    required CsvImportKind kind,
  }) {
    final errors = <CsvImportError>[];
    final rows = _CsvParser.parse(contents, errors);
    if (rows.isEmpty && errors.isEmpty) {
      errors.add(
        const CsvImportError(row: 1, field: '表格', message: '文件至少包含一条数据'),
      );
    }
    final requiredHeaders = kind == CsvImportKind.cards
        ? const {'record_type', 'category_type', 'category_name', 'card_number'}
        : const {
            'record_type',
            'category_type',
            'category_name',
            'id_number',
            'issuer',
          };
    if (rows.isNotEmpty) {
      final missing = requiredHeaders.where((h) => !rows.first.containsKey(h));
      for (final field in missing) {
        errors.add(CsvImportError(row: 1, field: field, message: '模板缺少必要列'));
      }
      final allowedHeaders = kind == CsvImportKind.cards
          ? _cardHeaders
          : _documentHeaders;
      for (final field in rows.first.keys) {
        if (!allowedHeaders.contains(field)) {
          errors.add(
            CsvImportError(row: 1, field: field, message: '不是该模板支持的列'),
          );
        }
      }
    }
    final now = DateTime.now();
    final categoriesById = {for (final c in categories) c.id: c};
    final categoriesByKey = {
      for (final c in categories) _categoryKey(c.cardType, c.name): c,
    };
    final pendingCategories = <String, BankCategory>{};
    final cards = <CardRecord>[];
    final documents = <DocumentRecord>[];
    final seenIds = <String>{};

    for (var index = 0; index < rows.length; index++) {
      final rowNumber = index + 2;
      final row = rows[index];
      try {
        if (kind == CsvImportKind.cards) {
          final card = _parseCard(
            row,
            rowNumber,
            now,
            categoriesById,
            categoriesByKey,
            pendingCategories,
          );
          if (!seenIds.add(card.id)) {
            throw _RowError('id', '文件中存在重复 ID');
          }
          cards.add(card);
        } else {
          final document = _parseDocument(
            row,
            rowNumber,
            now,
            categoriesById,
            categoriesByKey,
            pendingCategories,
          );
          if (!seenIds.add(document.id)) {
            throw _RowError('id', '文件中存在重复 ID');
          }
          documents.add(document);
        }
      } on _RowError catch (e) {
        errors.add(
          CsvImportError(row: rowNumber, field: e.field, message: e.message),
        );
      } catch (_) {
        errors.add(
          CsvImportError(row: rowNumber, field: '行', message: '数据格式无效'),
        );
      }
    }

    final allCategories = [...pendingCategories.values];
    return CsvImportDraft(
      kind: kind,
      snapshot: VaultSnapshot(
        categories: allCategories,
        cards: cards,
        documents: documents,
      ),
      totalRows: rows.length,
      errors: List.unmodifiable(errors),
      createdCategoryCount: allCategories.length,
    );
  }

  Future<ImportResult> commit(CsvImportDraft draft) {
    if (!draft.isValid) {
      throw StateError('CSV 预校验未通过');
    }
    return BackupService(database: database).importMerge(draft.snapshot);
  }

  CardRecord _parseCard(
    Map<String, String> row,
    int rowNumber,
    DateTime now,
    Map<String, BankCategory> categoriesById,
    Map<String, BankCategory> categoriesByKey,
    Map<String, BankCategory> pending,
  ) {
    final recordType = _optional(row['record_type']);
    if (recordType != null &&
        recordType != 'card' &&
        recordType != '卡片' &&
        recordType != '银行卡') {
      throw _RowError('record_type', '银行卡模板必须使用 card');
    }
    final type = _cardType(row['category_type'], rowNumber);
    final category = _resolveCategory(
      row,
      rowNumber,
      type,
      categoriesById,
      categoriesByKey,
      pending,
      now,
    );
    final number = CardNumberValidation.normalize(row['card_number'] ?? '');
    if (number == null) throw _RowError('card_number', '仅支持数字，长度 1-19 位');
    final expiry = _parseExpiry(row['expiry'], rowNumber);
    final cvv = _optional(row['cvv']);
    if (cvv != null && !RegExp(r'^\d{3}$').hasMatch(cvv)) {
      throw _RowError('cvv', 'CVV 应为 3 位数字');
    }
    final uShield = _parseSlashDate(row['u_shield_expiry'], 'u_shield_expiry');
    final note = _optional(row['note']);
    if (Validators.note(note) != null) throw _RowError('note', '备注最多 500 字');
    final id = _id(row['id'], now);
    final updatedAt = _timestamp(row['updated_at'], 'updated_at', now);
    return CardRecord(
      id: id,
      categoryId: category.id,
      cardType: type,
      cardNumber: number,
      holderName: _optional(row['holder_name']),
      expiryMonth: expiry?.$1,
      expiryYear: expiry?.$2,
      cvv: cvv,
      uShieldExpiryDate: uShield,
      note: note,
      createdAt: _timestamp(row['created_at'], 'created_at', now),
      updatedAt: updatedAt,
    );
  }

  DocumentRecord _parseDocument(
    Map<String, String> row,
    int rowNumber,
    DateTime now,
    Map<String, BankCategory> categoriesById,
    Map<String, BankCategory> categoriesByKey,
    Map<String, BankCategory> pending,
  ) {
    final rawType = _optional(row['category_type']);
    if (rawType != null && rawType != 'document' && rawType != '证件') {
      throw _RowError('category_type', '证件模板必须使用 document');
    }
    final category = _resolveCategory(
      row,
      rowNumber,
      CardType.document,
      categoriesById,
      categoriesByKey,
      pending,
      now,
    );
    final idNumber = DocumentIdFormatting.normalize(row['id_number'] ?? '');
    if (idNumber.isEmpty ||
        idNumber.length > DocumentRecord.maxIdNumberLength) {
      throw _RowError('id_number', '证件号仅支持数字，最长 20 位');
    }
    final issuer = _optional(row['issuer']);
    if (issuer == null) throw _RowError('issuer', '请输入签发机关');
    final permanent = (_optional(row['validity_permanent']) ?? '')
        .toLowerCase();
    final isPermanent =
        permanent == 'true' || permanent == '1' || permanent == '是';
    if (permanent.isNotEmpty &&
        !isPermanent &&
        permanent != 'false' &&
        permanent != '0' &&
        permanent != '否') {
      throw _RowError('validity_permanent', '只能填写 true/false');
    }
    final fromRaw = _optional(row['valid_from']);
    final toRaw = _optional(row['valid_to']);
    DateTime? from;
    DateTime? to;
    if (isPermanent) {
      if (fromRaw != null || toRaw != null) {
        throw _RowError('validity_permanent', '长期有效时日期必须为空');
      }
    } else {
      if (fromRaw == null || toRaw == null) {
        throw _RowError('valid_from', '非长期有效时必须填写起止日期');
      }
      from = DocumentRecord.parseDate(fromRaw);
      to = DocumentRecord.parseDate(toRaw);
      if (from == null || to == null || to.isBefore(from)) {
        throw _RowError('valid_from', '日期无效或结束日期早于开始日期');
      }
    }
    final id = _id(row['id'], now);
    return DocumentRecord(
      id: id,
      categoryId: category.id,
      holderName: _optional(row['holder_name']) ?? '',
      idNumber: idNumber,
      issuer: issuer,
      validFrom: from,
      validTo: to,
      validityIsPermanent: isPermanent,
      remark: _optional(row['remark'] ?? row['note']),
      createdAt: _timestamp(row['created_at'], 'created_at', now),
      updatedAt: _timestamp(row['updated_at'], 'updated_at', now),
    );
  }

  BankCategory _resolveCategory(
    Map<String, String> row,
    int rowNumber,
    CardType type,
    Map<String, BankCategory> byId,
    Map<String, BankCategory> byKey,
    Map<String, BankCategory> pending,
    DateTime now,
  ) {
    final categoryId = _optional(row['category_id']);
    if (categoryId != null) {
      final found = byId[categoryId];
      if (found == null || found.cardType != type) {
        throw _RowError('category_id', '分类不存在或类型不匹配');
      }
      return found;
    }
    final name = _optional(row['category_name']);
    if (Validators.categoryName(name) != null) {
      throw _RowError('category_name', '分类名必须是 1-4 个中文字符');
    }
    final key = _categoryKey(type, name!);
    return byKey[key] ??= pending[key] ??= BankCategory(
      id: const Uuid().v4(),
      cardType: type,
      name: name,
      sortOrder: byKey.length + pending.length,
      createdAt: now,
      updatedAt: now,
    );
  }

  CardType _cardType(String? raw, int row) {
    return switch (_optional(raw)) {
      'debit' || '借记卡' => CardType.debit,
      'credit' || '信用卡' => CardType.credit,
      _ => throw _RowError('category_type', '只能填写 debit/借记卡 或 credit/信用卡'),
    };
  }

  (int, int)? _parseExpiry(String? raw, int row) {
    final value = _optional(raw);
    if (value == null) return null;
    if (Validators.expiry(value) != null) {
      throw _RowError('expiry', '格式应为 MM/YY');
    }
    return (
      int.parse(value.substring(0, 2)),
      2000 + int.parse(value.substring(3)),
    );
  }

  DateTime? _parseSlashDate(String? raw, String field) {
    final value = _optional(raw);
    if (value == null) return null;
    if (Validators.uShieldDate(value) != null) {
      throw _RowError(field, '格式应为 yyyy/M/d');
    }
    final p = value.split('/');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  DateTime _timestamp(String? raw, String field, DateTime fallback) {
    final value = _optional(raw);
    if (value == null) return fallback;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw _RowError(field, '应为 ISO-8601 日期时间');
    return parsed;
  }

  String _id(String? raw, DateTime now) {
    final value = _optional(raw);
    if (value == null) return const Uuid().v4();
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw _RowError('id', 'ID 必须是 UUID');
    }
    return value;
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _categoryKey(CardType type, String name) =>
      '${type.name}|$name';

  static const _cardHeaders = {
    'record_type',
    'category_type',
    'category_name',
    'category_id',
    'id',
    'holder_name',
    'card_number',
    'expiry',
    'cvv',
    'u_shield_expiry',
    'note',
    'created_at',
    'updated_at',
  };

  static const _documentHeaders = {
    'record_type',
    'category_type',
    'category_name',
    'category_id',
    'id',
    'holder_name',
    'id_number',
    'issuer',
    'valid_from',
    'valid_to',
    'validity_permanent',
    'remark',
    'note',
    'created_at',
    'updated_at',
  };
}

final class _RowError implements Exception {
  _RowError(this.field, this.message);
  final String field;
  final String message;
}

final class _CsvParser {
  static const _headerAliases = {
    // 中文模板字段。
    '记录类型': 'record_type',
    '分类类型': 'category_type',
    '分类名称': 'category_name',
    '分类ID': 'category_id',
    '记录ID': 'id',
    '持有人姓名': 'holder_name',
    '卡号': 'card_number',
    '有效期': 'expiry',
    'CVV': 'cvv',
    'U盾到期日': 'u_shield_expiry',
    '备注': 'note',
    '证件号': 'id_number',
    '签发机关': 'issuer',
    '有效期起': 'valid_from',
    '有效期止': 'valid_to',
    '长期有效': 'validity_permanent',
    '创建时间': 'created_at',
    '更新时间': 'updated_at',
  };

  static List<Map<String, String>> parse(
    String contents,
    List<CsvImportError> errors,
  ) {
    final text = contents.startsWith('\uFEFF')
        ? contents.substring(1)
        : contents;
    final records = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    var afterQuote = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            afterQuote = true;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"' && cell.length == 0) {
        quoted = true;
      } else if (ch == ',') {
        row.add(cell.toString());
        cell = StringBuffer();
        afterQuote = false;
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        if (row.any((v) => v.isNotEmpty)) records.add(row);
        row = <String>[];
        cell = StringBuffer();
        afterQuote = false;
      } else if (afterQuote && ch.trim().isNotEmpty) {
        errors.add(
          const CsvImportError(row: 1, field: '表格', message: '引号格式无效'),
        );
        return const [];
      } else {
        cell.write(ch);
      }
    }
    if (quoted) {
      errors.add(const CsvImportError(row: 1, field: '表格', message: '引号未闭合'));
      return const [];
    }
    if (row.isNotEmpty || cell.length > 0) {
      row.add(cell.toString());
      if (row.any((v) => v.isNotEmpty)) records.add(row);
    }
    if (records.isEmpty) return const [];
    final headers = records.first.map(_normalizeHeader).toList();
    if (headers.any((h) => h.isEmpty) ||
        headers.toSet().length != headers.length) {
      errors.add(
        const CsvImportError(row: 1, field: '表头', message: '表头不能为空且不能重复'),
      );
      return const [];
    }
    final result = <Map<String, String>>[];
    for (var i = 1; i < records.length; i++) {
      if (records[i].length != headers.length) {
        errors.add(CsvImportError(row: i + 1, field: '行', message: '列数与表头不一致'));
        continue;
      }
      result.add({
        for (var j = 0; j < headers.length; j++) headers[j]: records[i][j],
      });
    }
    return result;
  }

  static String _normalizeHeader(String raw) {
    var header = raw.trim();
    // 模板用中文全角括号标记可选字段；也接受半角括号，便于用户编辑。
    header = header.replaceFirst(RegExp(r'\s*[（(][^（）()]*[）)]\s*$'), '');
    return _headerAliases[header] ?? header;
  }
}
