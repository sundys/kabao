import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/clipboard_service.dart';
import '../../../../shared/utils/document_id_utils.dart';
import '../../../../shared/widgets/confirm_dialog_actions.dart';
import '../../domain/document.dart';
import '../../logic/documents_controller.dart';

class DocumentDetailPage extends ConsumerWidget {
  const DocumentDetailPage({super.key, required this.document});

  /// 路由传入的初始快照。展示数据来自 [documentRecordProvider]，编辑保存后
  /// 会重新读取，避免停留在旧值。
  final DocumentRecord document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 读取失败（例如证件已被删除）时回退到路由快照。
    final current =
        ref.watch(documentRecordProvider(document.id)).value ?? document;
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (current.holderName.isNotEmpty) ('姓名', current.holderName),
      ('证件号', DocumentIdFormatting.groupForDisplay(current.idNumber)),
      if (current.issuer.isNotEmpty) ('签发机关', current.issuer),
      ('有效期限', current.validityLabel),
      if (current.remark != null && current.remark!.isNotEmpty)
        ('备注', current.remark!),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('证件详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => context.push(
              '/wallet/document/edit',
              extra: (document: current, isNew: false),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 选项名：加粗。
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SelectableText(
                      value,
                      // 姓名、证件号、有效期限加粗显示。
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            label == '姓名' || label == '证件号' || label == '有效期限'
                            ? FontWeight.w700
                            : FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (label == '证件号')
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: '复制证件号',
                      onPressed: () => ClipboardService.copyCardNumber(
                        context,
                        ref,
                        document.idNumber,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除证件'),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除证件'),
        content: const Text('删除后无法恢复，确定删除这个证件吗？'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          ConfirmDialogActions(
            confirmLabel: '删除',
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onConfirm: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final ok = await ref
        .read(documentsProvider(document.categoryId).notifier)
        .delete(document.id);
    if (ok && context.mounted) {
      context.pop();
    }
  }
}
