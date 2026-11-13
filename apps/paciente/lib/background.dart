import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'state/app_state.dart';

const _task = 'nutrivitta.verificar';

/// Ponto de entrada da verificação em segundo plano (roda sem a tela do app).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Background.check();
    } catch (e) {
      debugPrint('Verificação em segundo plano: $e');
    }
    return true;
  });
}

/// Avisos ao paciente: pedido de conexão de nutricionista e recado novo.
///
/// Sem servidor (plano gratuito do Firebase), o Android roda esta verificação
/// mais ou menos a cada 15 minutos; com o app aberto, a sincronização já traz
/// tudo na hora.
class Background {
  Background._();

  static final instance = Background._();

  static const _kNotified = 'nv_notified_v1';
  static const _kEnabled = 'nv_background_v1';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _pluginReady = false;

  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!supported) return;
    try {
      await Workmanager().initialize(callbackDispatcher);
      await _initPlugin();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kEnabled) ?? false) await _register();
    } catch (e) {
      debugPrint('Segundo plano: $e');
    }
  }

  static Future<void> _initPlugin() async {
    if (_pluginReady) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_nv'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _pluginReady = true;
  }

  /// Liga a verificação (depois do login) e pede permissão de notificação.
  Future<void> enable() async {
    if (!supported) return;
    try {
      await _initPlugin();
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, true);
      await _register();
    } catch (e) {
      debugPrint('Segundo plano: $e');
    }
  }

  Future<void> disable() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, false);
      await Workmanager().cancelByUniqueName(_task);
    } catch (e) {
      debugPrint('Segundo plano: $e');
    }
  }

  Future<void> _register() => Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  /// Com o app aberto, o que já aparece na tela não precisa virar notificação.
  Future<void> markSeen(AppState state) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = {...(prefs.getStringList(_kNotified) ?? const [])};
    for (final l in state.pendingLinks) {
      seen.add('link:${l.id}:${l.updatedAt}');
    }
    for (final c in state.comments.values) {
      seen.add('comment:${c.date}:${c.updatedAt}');
    }
    await prefs.setStringList(_kNotified, _trim(seen));
  }

  static List<String> _trim(Set<String> s) {
    final l = s.toList();
    return l.length > 300 ? l.sublist(l.length - 300) : l;
  }

  /// Confere pedidos e recados novos e mostra as notificações.
  static Future<void> check() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kEnabled) ?? false)) return;
    final session = await Account.background(prefs);
    if (session == null) return;
    final (uid, db) = session;
    final remote = Remote(db);
    final seen = {...(prefs.getStringList(_kNotified) ?? const [])};
    final notes = <(String, String)>[];

    for (final l in await remote.linksOfPatient(uid)) {
      if (!l.pending) continue;
      final key = 'link:${l.id}:${l.updatedAt}';
      if (!seen.add(key)) continue;
      final who = l.proName.isEmpty ? 'Um nutricionista' : l.proName;
      notes.add(('$who quer acompanhar sua alimentação', 'Abra o NutriVitta para aceitar ou recusar o pedido.'));
    }
    final comments = await remote.comments(uid);
    for (final c in comments.values) {
      final key = 'comment:${c.date}:${c.updatedAt}';
      if (!seen.add(key)) continue;
      final who = c.author.isEmpty ? 'seu nutricionista' : c.author;
      notes.add(('Recado de $who', c.text));
    }
    await prefs.setStringList(_kNotified, _trim(seen));
    if (notes.isEmpty) return;

    await _initPlugin();
    for (final (i, (title, body)) in notes.take(5).indexed) {
      await _plugin.show(
        id: 100 + i,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'nutricionista',
            'Nutricionista',
            channelDescription: 'Pedidos de conexão e recados do nutricionista',
            importance: Importance.high,
            priority: Priority.high,
            color: NvColors.green,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    }
  }
}
