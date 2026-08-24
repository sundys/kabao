import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/reminder_rules.dart';
import '../../logic/notifications_provider.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    final action = await showModalBottomSheet<_NotificationAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.done_all_outlined),
              title: Text(notification.isRead ? '标为未读' : '标为已读'),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_NotificationAction.toggleRead),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.close_outlined),
              title: Text('取消'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_NotificationAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }
    final controller = ref.read(notificationsProvider.notifier);
    switch (action) {
      case _NotificationAction.toggleRead:
        await controller.markRead(notification);
      case _NotificationAction.delete:
        // Deletion requires an explicit confirmation against mis-taps.
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除通知'),
            content: const Text('删除后无法恢复，确定删除这条通知吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await controller.delete(notification);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('加载失败，请重试')),
        data: (notifications) {
          if (notifications.isEmpty) {
            final theme = Theme.of(context);
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_outlined,
                    size: 72,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无通知',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(notificationsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  notification: notification,
                  onLongPress: () => _showActions(context, ref, notification),
                  onToggleRead: () => ref
                      .read(notificationsProvider.notifier)
                      .markRead(notification),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

enum _NotificationAction { toggleRead, delete }

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onLongPress,
    required this.onToggleRead,
  });

  final AppNotification notification;
  final VoidCallback onLongPress;
  final VoidCallback onToggleRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !notification.isRead;
    return Material(
      color: unread
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onLongPress,
        onTap: unread ? onToggleRead : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (notification.type) {
                  ReminderType.cardExpiry => Icons.credit_card,
                  ReminderType.uShieldExpiry => Icons.shield_outlined,
                  ReminderType.documentExpiry => Icons.badge_outlined,
                },
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            notification.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(notification.body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                icon: unread
                    ? const Icon(Icons.mark_email_read_outlined)
                    : const Icon(Icons.mark_email_unread_outlined),
                tooltip: unread ? '标为已读' : '标为未读',
                onPressed: onToggleRead,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
