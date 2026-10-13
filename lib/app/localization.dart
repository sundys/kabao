import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 应用界面语言。
///
/// 业务文案目前是硬编码中文，这里同时把 Flutter 内置组件的文案（文本框长按
/// 菜单、日期选择器、对话框语义标签等）固定为中文，避免出现中英文混排。
const Locale appLocale = Locale('zh', 'CN');

/// 仅声明中文：未匹配到设备语言时，Flutter 会回退到首个受支持的语言。
const List<Locale> appSupportedLocales = <Locale>[appLocale];

/// Flutter 内置组件的本地化代理，缺少它们时内置菜单会退回英文。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
