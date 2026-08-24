import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    _nameController = TextEditingController(text: doc.holderName);
    _idNumberController = TextEditingController(text: doc.idNumber);
    _issuerController = TextEditingController(text: doc.issuer);
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
      final parts = _validityController.text.trim().split('-');
      // 防御性清理：剔除可能被输入法带入的多余符号。
      final issuer = _issuerController.text.trim().replaceFirst(
        RegExp(r'^\$+'),
        '',
      );
      final saved = widget.document.copyWith(
        holderName: _nameController.text.trim(),
        idNumber: _idNumberController.text.trim(),
        issuer: issuer,
        validFrom: DocumentRecord.parseDate(parts[0]),
        validTo: DocumentRecord.parseDate(parts[1]),
        updatedAt: DateTime.now(),
      );
      // 备注单独保存（copyWith 不处理可空覆盖）。
      final withRemark = DocumentRecord(
        id: saved.id,
        categoryId: saved.categoryId,
        holderName: saved.holderName,
        idNumber: saved.idNumber,
        issuer: saved.issuer,
        validFrom: saved.validFrom,
        validTo: saved.validTo,
        remark: _remarkController.text.trim().isEmpty
            ? null
            : _remarkController.text.trim(),
        createdAt: saved.createdAt,
        updatedAt: saved.updatedAt,
        modelVersion: saved.modelVersion,
      );
      final ok = await ref
          .read(documentsProvider(widget.document.categoryId).notifier)
          .save(withRemark);
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
              maxLength: DocumentRecord.maxIdNumberLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '证件号',
                hintText: '连续输入数字即可',
                counterText: '',
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty || !RegExp(r'^\d{1,20}$').hasMatch(value)) {
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
              controller: _validityController,
              keyboardType: TextInputType.datetime,
              inputFormatters: const [
                // yyyy.MM.dd-yyyy.MM.dd: 4+2+2 | - | 4+2+2 = 16 digits.
                SeparatorAutoFormatter(
                  [4, 2, 2, 4, 2, 2],
                  ['.', '.', '-', '.', '.'],
                ),
              ],
              decoration: const InputDecoration(
                labelText: '有效期限',
                hintText: '2016.08.08-2036.08.08',
              ),
              validator: Validators.documentValidityRange,
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
