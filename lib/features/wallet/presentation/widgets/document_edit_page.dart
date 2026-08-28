import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/document_id_utils.dart';
import '../../../../shared/validation/validators.dart';
import '../../../../shared/widgets/input_formatters.dart';
import '../../domain/document.dart';
import '../../logic/documents_controller.dart';

/// Add/edit form for a certificate document.
class DocumentEditPage extends ConsumerStatefulWidget {
  const DocumentEditPage({
    super.key,
    required this.document,
    required this.isNew,
  });

  final DocumentRecord document;
  final bool isNew;

  @override
  ConsumerState<DocumentEditPage> createState() => _DocumentEditPageState();
}

class _DocumentEditPageState extends ConsumerState<DocumentEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _idNumberController;
  late final TextEditingController _issuerController;
  late final TextEditingController _validityController;
  late final TextEditingController _remarkController;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _permanentValidity = false;

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    _nameController = TextEditingController(text: doc.holderName);
    _idNumberController = TextEditingController(
      text: DocumentIdFormatting.groupForDisplay(doc.idNumber),
    );
    _issuerController = TextEditingController(text: doc.issuer);
    _permanentValidity = doc.validityIsPermanent;
    _validityController = TextEditingController(
      text: doc.validFrom == null || doc.validTo == null
          ? ''
          : '${DocumentRecord.formatDate(doc.validFrom!)}-'
                '${DocumentRecord.formatDate(doc.validTo!)}',
    );
    _remarkController = TextEditingController(text: doc.remark ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idNumberController.dispose();
    _issuerController.dispose();
    _validityController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      // 防御性清理：剔除可能被输入法带入的多余符号。
      final issuer = _issuerController.text.trim().replaceFirst(
        RegExp(r'^\$+'),
        '',
      );
      DateTime? validFrom;
      DateTime? validTo;
      if (!_permanentValidity) {
        final parts = _validityController.text.trim().split('-');
        validFrom = DocumentRecord.parseDate(parts[0]);
        validTo = DocumentRecord.parseDate(parts[1]);
      }
      // 证件号入库前归一为纯数字，分组只是显示层的事。
      final idNumber = DocumentIdFormatting.normalize(_idNumberController.text);
      final now = DateTime.now();
      final source = widget.document;
      final saved = DocumentRecord(
        id: source.id,
        categoryId: source.categoryId,
        holderName: _nameController.text.trim(),
        idNumber: idNumber,
        issuer: issuer,
        // 长期有效时两个日期都写空，覆盖掉此前录入过的日期。
        validFrom: validFrom,
        validTo: validTo,
        validityIsPermanent: _permanentValidity,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
        createdAt: source.createdAt,
        updatedAt: now,
        modelVersion: source.modelVersion,
      );
      final ok = await ref
          .read(documentsProvider(widget.document.categoryId).notifier)
          .save(saved);
      if (!mounted) {
        return;
      }
      if (ok) {
        context.pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isNew ? '添加证件' : '编辑证件')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              maxLength: 20,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '姓名',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('doc-id-number'),
              controller: _idNumberController,
              keyboardType: TextInputType.number,
              inputFormatters: const [
                // 402356 20120226 3038：6 + 8 + 剩余，分组只影响显示，
                // 存库与复制都是连续数字。
                SeparatorAutoFormatter(DocumentIdFormatting.groupSizes, [
                  DocumentIdFormatting.separator,
                  DocumentIdFormatting.separator,
                ]),
              ],
              decoration: const InputDecoration(
                labelText: '证件号',
                hintText: '连续输入数字，自动按 6/8/尾号分组',
                counterText: '',
              ),
              validator: (v) {
                final digits = DocumentIdFormatting.normalize(v ?? '');
                if (digits.isEmpty ||
                    digits.length > DocumentRecord.maxIdNumberLength) {
                  return '证件号仅支持数字，最长 ${DocumentRecord.maxIdNumberLength} 位';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _issuerController,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '签发机关',
                hintText: '如：中南县公安局',
                counterText: '',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入签发机关' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('doc-validity'),
              controller: _validityController,
              enabled: !_permanentValidity,
              keyboardType: TextInputType.datetime,
              inputFormatters: const [
                // yyyy.MM.dd-yyyy.MM.dd: 4+2+2 | - | 4+2+2 = 16 digits.
                SeparatorAutoFormatter(
                  [4, 2, 2, 4, 2, 2],
                  ['.', '.', '-', '.', '.'],
                ),
              ],
              decoration: InputDecoration(
                labelText: '有效期限',
                hintText: _permanentValidity
                    ? '已选长期有效'
                    : '2016.08.08-2036.08.08',
              ),
              // 勾选长期有效后不再校验日期格式。
              validator: _permanentValidity
                  ? null
                  : Validators.documentValidityRange,
            ),
            CheckboxListTile(
              key: const Key('doc-permanent-validity'),
              value: _permanentValidity,
              title: const Text(DocumentRecord.permanentValidityLabel),
              subtitle: const Text('勾选后清空并锁定上方日期，保存为「长期有效」'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              onChanged: (checked) {
                setState(() {
                  _permanentValidity = checked ?? false;
                  if (_permanentValidity) {
                    // 立即清空，避免残留日期在取消勾选后被误当成有效输入。
                    _validityController.clear();
                  }
                });
                // 切换后重跑校验，清掉上一次的日期格式错误提示。
                _formKey.currentState?.validate();
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _remarkController,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '备注',
                alignLabelWithHint: true,
                hintText: '选填',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('doc-save'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
