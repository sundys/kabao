import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../app/app_routes.dart';
import '../../../../app/theme/theme_mode_controller.dart';
import '../../../auth/logic/auth_controller.dart';
import '../../../auth/models/auth_state.dart';
import '../../../backup/presentation/backup_flows.dart';
import '../../../backup/logic/csv_import_service.dart';
import '../../../../shared/services/local_notification_service.dart';
import '../../../../shared/widgets/confirm_dialog_actions.dart';
import '../../logic/lock_timeout_controller.dart';
import '../../logic/wipe_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool? _biometricsSupported;

  @override
  void initState() {
    super.initState();
    _localAuth.isDeviceSupported().then((supported) {
      if (mounted) {
        setState(() => _biometricsSupported = supported);
      }
    });
  }

  String _themeLabel(WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    return switch (mode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '暗色',
      ThemeMode.system => '跟随系统',
    };
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider).value ?? ThemeMode.system;
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('主题颜色'),
        children: [
          for (final (mode, label) in [
            (ThemeMode.light, '浅色'),
            (ThemeMode.dark, '暗色'),
            (ThemeMode.system, '跟随系统颜色设定'),
          ])
            ListTile(
              leading: Icon(switch (mode) {
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.system => Icons.brightness_auto_outlined,
              }),
              title: Text(label),
              trailing: mode == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(dialogContext).pop(mode),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      await ref.read(themeModeProvider.notifier).setMode(selected);
    }
  }

  /// 单选弹窗：实心圆点为当前档位，空心圆圈为未选中。选择后立即持久化，
  /// 状态一直保留到用户改选其它档位。
  Future<void> _pickLockTimeout(BuildContext context, WidgetRef ref) async {
    final current = ref.read(lockTimeoutProvider).value ?? LockTimeout.fallback;
    final selected = await showDialog<LockTimeout>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('超时时间'),
        children: [
          for (final timeout in LockTimeout.values)
            ListTile(
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(
                timeout == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: timeout == current
                    ? Theme.of(dialogContext).colorScheme.primary
                    : null,
              ),
              title: Text(timeout.label),
              selected: timeout == current,
              onTap: () => Navigator.of(dialogContext).pop(timeout),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      await ref.read(lockTimeoutProvider.notifier).setTimeout(selected);
    }
  }

  Future<void> _toggleBiometric(bool enabled) async {
    final authState = ref.read(authControllerProvider).value;
    if (enabled) {
      if (authState is! AuthUnlocked || !mounted) {
        return;
      }
      // 开启前必须验证 APP 主密码，防止陌生人随意添加指纹。
      final password = await _askMasterPassword(context);
      if (password == null || !mounted) {
        return;
      }
      final verified = await ref
          .read(authControllerProvider.notifier)
          .verifyPassword(password);
      if (!mounted) {
        return;
      }
      if (!verified) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('主密码错误，未开启')));
        return;
      }
      await ref
          .read(authControllerProvider.notifier)
          .setBiometricEnabled(true, dataKey: authState.dataKey);
    } else {
      await ref
          .read(authControllerProvider.notifier)
          .setBiometricEnabled(false);
    }
    if (mounted) {
      // 刷新开关状态显示。
      ref.invalidate(biometricEnabledProvider);
    }
  }

  Future<String?> _askMasterPassword(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('验证主密码'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '开启生物识别解锁前，请先输入主密码确认身份。',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
              TextFormField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
                enableSuggestions: false,
                autocorrect: false,
                validator: (v) => (v == null || v.isEmpty) ? '请输入主密码' : null,
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          ConfirmDialogActions(
            confirmLabel: '确认',
            destructive: false,
            onCancel: () => Navigator.of(dialogContext).pop(),
            onConfirm: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Irreversible wipe: double confirmation, then business data, database
  /// file and all key material. The app returns to first-run setup.
  Future<void> _wipeAllData() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部数据'),
        content: const Text(
          '所有卡片、分类、通知与主密码都将被永久删除，'
          '此操作无法撤销。建议先导出备份。\n\n确定继续吗？',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          _WipeConfirmationActions(
            dialogContext: dialogContext,
            confirmLabel: '继续',
          ),
        ],
      ),
    );
    if (first != true || !mounted) {
      return;
    }
    final second = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('再次确认'),
        content: const Text('真的要删除全部数据吗？删除后将回到首次设置。'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          _WipeConfirmationActions(
            dialogContext: dialogContext,
            confirmLabel: '全部删除',
          ),
        ],
      ),
    );
    if (second != true) {
      return;
    }
    await ref.read(wipeServiceProvider).wipeAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometricEnabled = ref.watch(biometricEnabledProvider).value ?? false;
    final lockTimeout =
        ref.watch(lockTimeoutProvider).value ?? LockTimeout.fallback;
    final lockTimeoutSubtitle = lockTimeout == LockTimeout.immediate
        ? '切换后台后立即锁定数据库'
        : '切换后台 ${lockTimeout.label}后锁定数据库';
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _SectionLabel('外观'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: '主题颜色',
                subtitle: _themeLabel(ref),
                onTap: () => _pickTheme(context, ref),
              ),
            ],
          ),
          const _SectionLabel('安全'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.password_outlined,
                title: '修改主密码',
                subtitle: '重新派生密钥并迁移加密数据',
                accent: theme.colorScheme.tertiary,
                onTap: () => context.push(AppRoutes.changePassword),
              ),
              _SettingsSwitchTile(
                icon: Icons.fingerprint,
                title: '生物识别登录',
                subtitle: _biometricsSupported == false
                    ? '当前设备不支持'
                    : '使用指纹快速解锁',
                accent: theme.colorScheme.tertiary,
                value: biometricEnabled,
                onChanged: _biometricsSupported == true
                    ? _toggleBiometric
                    : null,
              ),
              _SettingsTile(
                icon: Icons.timer_outlined,
                title: '超时时间',
                subtitle: lockTimeoutSubtitle,
                accent: theme.colorScheme.tertiary,
                onTap: () => _pickLockTimeout(context, ref),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: '系统通知',
                subtitle: '管理到期提醒在 Android 通知栏的显示权限',
                accent: theme.colorScheme.tertiary,
                onTap: () async {
                  await LocalNotificationService.instance.initialize();
                  await LocalNotificationService.instance.openSettings();
                },
              ),
            ],
          ),
          const _SectionLabel('数据'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.file_download_outlined,
                title: '导入备份',
                subtitle: '从加密的 .kabao 备份文件恢复',
                accent: theme.colorScheme.secondary,
                onTap: () => BackupFlows.import(context, ref),
              ),
              _SettingsTile(
                icon: Icons.file_upload_outlined,
                title: '导出备份',
                subtitle: '导出为独立加密的 .kabao 文件',
                accent: theme.colorScheme.secondary,
                onTap: () => BackupFlows.export(context, ref),
              ),
              _SettingsTile(
                icon: Icons.table_rows_outlined,
                title: '导入银行卡 CSV',
                subtitle: '按标准模板批量导入借记卡或信用卡',
                accent: theme.colorScheme.secondary,
                onTap: () =>
                    BackupFlows.importCsv(context, ref, CsvImportKind.cards),
              ),
              _SettingsTile(
                icon: Icons.badge_outlined,
                title: '导入证件 CSV',
                subtitle: '按标准模板批量导入证件卡',
                accent: theme.colorScheme.secondary,
                onTap: () => BackupFlows.importCsv(
                  context,
                  ref,
                  CsvImportKind.documents,
                ),
              ),
              _SettingsTile(
                icon: Icons.cloud_sync_outlined,
                title: 'WebDAV 备份',
                subtitle: '服务器地址、测试连接与自动备份策略',
                accent: theme.colorScheme.secondary,
                onTap: () => context.push(AppRoutes.webdav),
              ),
            ],
          ),
          const _SectionLabel('危险操作'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.dangerous_outlined,
                title: '清空全部数据',
                subtitle: '删除所有卡片、通知与密钥，不可恢复',
                destructive: true,
                onTap: _wipeAllData,
              ),
            ],
          ),
          const _SectionLabel('关于'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                title: '关于卡包',
                subtitle: '版本信息、开源主页与更新',
                accent: theme.colorScheme.onSurfaceVariant,
                onTap: () => context.push(AppRoutes.about),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分组小标题：低饱和、加字距，作为卡片组之间的视觉分隔。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// 一组设置项：圆角容器 + 项目间细分隔线，替代原来零散的整行分隔线。
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  /// 与 [_SettingsTile] 的图标块对齐：内容左内边距 14 + 图标 36 + 间距 12。
  static const double _dividerIndent = 62;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = scheme.onSurface.withValues(alpha: isDark ? .10 : .07);
    // 用 Material 而不是带色 Container：ListTile 的水波纹画在最近的 Material
    // 上，若中间夹一层有色 DecoratedBox，点击反馈会被遮住（Flutter 会断言）。
    return Material(
      color: scheme.onSurface.withValues(alpha: isDark ? .05 : .035),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: isDark ? .08 : .05),
          ),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: _dividerIndent,
                  endIndent: 14,
                  color: dividerColor,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 带彩色图标底纹的设置项。功能与 [ListTile] 一致，仅统一了视觉与间距。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.accent,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// 图标底纹与图标本身的强调色；默认取主题主色。
  final Color? accent;

  /// 危险操作：图标、标题与底纹都使用错误色。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = destructive ? scheme.error : (accent ?? scheme.primary);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      minVerticalPadding: 12,
      leading: _IconChip(icon: icon, color: color),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: destructive ? scheme.error : scheme.onSurface,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: scheme.onSurfaceVariant.withValues(alpha: .45),
      ),
      onTap: onTap,
    );
  }
}

/// 开关型设置项，图标底纹与 [_SettingsTile] 保持一致。
class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.onChanged,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      secondary: _IconChip(icon: icon, color: accent ?? scheme.primary),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 36×36 的圆角图标底纹，用低透明度强调色区分不同分组。
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

/// Equal-width, separated actions for the destructive confirmation dialogs.
class _WipeConfirmationActions extends StatelessWidget {
  const _WipeConfirmationActions({
    required this.dialogContext,
    required this.confirmLabel,
  });

  final BuildContext dialogContext;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(dialogContext).colorScheme;
    final cancelBorder = Color.alphaBlend(
      Colors.white.withValues(alpha: .65),
      scheme.primary,
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              side: BorderSide(color: cancelBorder, width: 1.5),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ),
      ],
    );
  }
}
