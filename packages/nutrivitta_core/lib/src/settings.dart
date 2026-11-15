import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/nv_theme.dart';

/// Cor de destaque do app (botões, seleção, links).
enum Accent {
  green('Verde', NvColors.green),
  teal('Petróleo', NvColors.teal),
  blue('Azul', Color(0xFF2F6FDB)),
  purple('Roxo', Color(0xFF6B3FD4)),
  pink('Rosa', Color(0xFFC2407A)),
  orange('Laranja', Color(0xFFD9701E));

  const Accent(this.label, this.color);

  final String label;
  final Color color;
}

/// Tamanhos de texto oferecidos.
const textScales = [(1.0, 'Normal'), (1.12, 'Grande'), (1.25, 'Maior')];

/// Preferências de aparência, guardadas no aparelho.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this.defaultAccent) : accent = defaultAccent {
    _restore();
  }

  static const _key = 'nv_settings_v1';

  /// As preferências carregadas ao abrir o app.
  static late AppSettings instance;

  static Future<AppSettings> load({Accent defaultAccent = Accent.green}) async =>
      instance = AppSettings._(await SharedPreferences.getInstance(), defaultAccent);

  final SharedPreferences _prefs;
  final Accent defaultAccent;

  ThemeMode themeMode = ThemeMode.system;
  Accent accent;
  double textScale = 1.0;

  void _restore() {
    final s = _prefs.getString(_key);
    if (s == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(s) as Map);
      themeMode = ThemeMode.values.firstWhere((t) => t.name == m['theme'], orElse: () => ThemeMode.system);
      accent = Accent.values.firstWhere((a) => a.name == m['accent'], orElse: () => defaultAccent);
      final scale = (m['textScale'] as num?)?.toDouble() ?? 1.0;
      textScale = textScales.any((t) => t.$1 == scale) ? scale : 1.0;
    } catch (e) {
      debugPrint('Falha ao ler configurações: $e');
    }
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setString(_key, jsonEncode({'theme': themeMode.name, 'accent': accent.name, 'textScale': textScale}));
  }

  Future<void> setThemeMode(ThemeMode v) {
    themeMode = v;
    return _save();
  }

  Future<void> setAccent(Accent v) {
    accent = v;
    return _save();
  }

  Future<void> setTextScale(double v) {
    textScale = v;
    return _save();
  }

  ThemeData lightTheme() => buildNvTheme(Brightness.light, accent: accent.color);
  ThemeData darkTheme() => buildNvTheme(Brightness.dark, accent: accent.color);

  /// Aplica o tamanho do texto escolhido (usar em MaterialApp.builder).
  Widget applyTextScale(BuildContext context, Widget child) {
    if (textScale == 1.0) return child;
    final mq = MediaQuery.of(context);
    return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(textScale)), child: child);
  }
}
