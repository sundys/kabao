import 'dart:io';

import 'package:flutter/services.dart';

/// Android 侧「安装未知应用」与 APK 安装的封装。
///
/// 仅 Android 可用；其它平台一律返回不支持，调用方据此降级为打开浏览器下载。
final class ApkInstaller {
  const ApkInstaller._();

  static const MethodChannel _channel = MethodChannel(
    'com.sundys.kabao/apk_installer',
  );

  static bool get isSupported => Platform.isAndroid;

  /// 是否已获得「安装未知应用」授权（Android 8.0 以下恒为 true）。
  static Future<bool> canInstallPackages() async {
    if (!isSupported) {
      return false;
    }
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  /// 跳转到系统设置申请安装权限。返回时不会给出结果，调用方需在应用恢复
  /// 前台后重新调用 [canInstallPackages] 确认。
  static Future<void> openInstallPermissionSettings() async {
    if (!isSupported) {
      return;
    }
    await _channel.invokeMethod<void>('requestInstallPermission');
  }

  /// 调用系统安装器安装已下载到本地缓存的 APK。
  static Future<bool> install(String apkPath) async {
    if (!isSupported) {
      return false;
    }
    return await _channel.invokeMethod<bool>('installApk', {'path': apkPath}) ??
        false;
  }

  /// 设备支持的 ABI 列表，顺序即优先级（与 Build.SUPPORTED_ABIS 一致）。
  static Future<List<String>> supportedAbis() async {
    if (!isSupported) {
      return const [];
    }
    final result = await _channel.invokeMethod<List<Object?>>('supportedAbis');
    return [
      for (final item in result ?? const <Object?>[])
        if (item is String) item,
    ];
  }
}
