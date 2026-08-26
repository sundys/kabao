import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/input_formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/card_number_utils.dart';
import '../../../../shared/validation/validators.dart';
import '../../domain/models.dart';
import '../../logic/cards_controller.dart';

/// Add/edit form for a card. On save, the card number is normalized to
/// digits-only; validation failures keep the user's input intact.
class CardEditPage extends ConsumerStatefulWidget {
  const CardEditPage({super.key, required this.card, required this.isNew});

  final CardRecord card;
  final bool isNew;

  @override
  ConsumerState<CardEditPage> createState() => _CardEditPageState();
}

class _CardEditPageState extends ConsumerState<CardEditPage> {
  late final TextEditingController _numberController;
  late final TextEditingController _expiryController;
  late final TextEditingController _cvvController;
  late final TextEditingController _uShieldController;
  late final TextEditingController _noteController;

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _nameController = TextEditingController(text: card.holderName ?? '');
    _numberController = TextEditingController(
      text: CardNumberValidation.groupForDisplay(card.cardNumber),
    );
    _expiryController = TextEditingController(
      text: card.expiryMonth != null && card.expiryYear != null
          ? '${card.expiryMonth.toString().padLeft(2, '0')}'
                '/${(card.expiryYear! % 100).toString().padLeft(2, '0')}'
          : '',
    );
    _cvvController = TextEditingController(text: card.cvv ?? '');
    _uShieldController = TextEditingController(
      text: card.uShieldExpiryDate == null
          ? ''
          : '${card.uShieldExpiryDate!.year}/'
                '${card.uShieldExpiryDate!.month.toString().padLeft(2, '0')}/'
                '${card.uShieldExpiryDate!.day.toString().padLeft(2, '0')}',
    );
    _noteController = TextEditingController(text: card.note ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _uShieldController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      final number =
          CardNumberValidation.normalize(_numberController.text) ?? '';
      final holderName = _nameController.text.trim();
      int? month;
      int? year;
      if (_expiryController.text.trim().isNotEmpty) {
        month = int.parse(_expiryController.text.substring(0, 2));
        year = 2000 + int.parse(_expiryController.text.substring(3));
      }
      String? uShieldWire;
      DateTime? uShieldDate;
      if (_uShieldController.text.trim().isNotEmpty) {
        uShieldWire = _uShieldController.text.trim();
        final parts = uShieldWire.split('/');
        uShieldDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }

      final saved = CardRecord(
        id: widget.card.id,
        categoryId: widget.card.categoryId,
        cardType: widget.card.cardType,
        cardNumber: number,
        holderName: holderName.isEmpty ? null : holderName,
        expiryMonth: month,
        expiryYear: year,
        cvv: _cvvController.text.trim().isEmpty
            ? null
            : _cvvController.text.trim(),
        uShieldExpiryDate: uShieldDate,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        createdAt: widget.card.createdAt,
        updatedAt: DateTime.now(),
        modelVersion: widget.card.modelVersion,
      );
      final ok = await ref
          .read(cardsProvider(widget.card.categoryId).notifier)
          .save(saved);
      if (!mounted) {
        return;
      }
      if (ok) {
        if (widget.isNew) {
          context.pop();
        } else {
          context.pop();
        }
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
      appBar: AppBar(title: Text(widget.isNew ? '添加卡片' : '编辑卡片')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('card-name-field'),
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
              key: const Key('card-number-field'),
              controller: _numberController,
              keyboardType: TextInputType.number,
              maxLength: 23, // 19 digits + separators
              inputFormatters: const [DigitGroupingFormatter()],
              autofillHints: const [AutofillHints.creditCardNumber],
              decoration: const InputDecoration(
                labelText: '卡号',
                hintText: '按 4 位分组输入',
                counterText: '',
              ),
              validator: Validators.cardNumber,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('card-expiry-field'),
                    controller: _expiryController,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: const [
                      BoundedSeparatorAutoFormatter(
                        [2, 2],
                        ['/'],
                        minValues: [1, null],
                        maxValues: [12, null],
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: '有效期 (MM/YY)',
                      hintText: '08/29',
                    ),
                    validator: Validators.expiry,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('card-cvv-field'),
                    controller: _cvvController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 3,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'CVV',
                      counterText: '',
                    ),
                    validator: Validators.cvv,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('card-u-shield-field'),
              controller: _uShieldController,
              keyboardType: TextInputType.datetime,
              inputFormatters: const [
                BoundedSeparatorAutoFormatter(
                  [4, 2, 2],
                  ['/', '/', '/'],
                  minValues: [2000, 1, 1],
                  maxValues: [2999, 12, 31],
                  requiredPrefixes: ['2', null, null],
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'U 盾证书到期日 (yyyy/MM/dd)',
                hintText: '2027/03/08',
              ),
              validator: Validators.uShieldDate,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('card-note-field'),
              controller: _noteController,
              maxLines: 3,
              maxLength: CardRecordNoteLimit.max,
              decoration: const InputDecoration(
                labelText: '备注',
                alignLabelWithHint: true,
              ),
              validator: Validators.note,
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
