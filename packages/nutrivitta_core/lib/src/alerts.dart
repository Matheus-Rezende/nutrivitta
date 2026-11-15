import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// Uma novidade a avisar. [key] identifica a novidade para avisar uma vez só.
class Alert {
  const Alert(this.key, this.title, this.body);

  final String key;
  final String title;
  final String body;
}

/// Notificações locais e verificação periódica em segundo plano.
///
/// Sem servidor (plano gratuito do Firebase), não há push instantâneo:
/// - com o app aberto, cada app verifica a cada poucos segundos;
/// - com o app fechado, o Android roda a verificação mais ou menos a cada
///   15 minutos (pode atrasar em economia de bateria).
/// Cada novidade vira uma notificação uma única vez, esteja o app aberto ou não.
class Alerts {
  Alerts._();

  static const _kSeen = 'nv_notified_v1';
  static const _kSeeded = 'nv_notified_seeded_v1';
  static const _kEnabled = 'nv_background_v1';
  static const task = 'nutrivitta.verificar';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Canal e cor das notificações deste app.
  static String channelId = 'avisos';
  static String channelName = 'Avisos';
  static String channelDescription = '';
  static Color color = const Color(0xFF1E7F4F);

  static Future<void> _init() async {
    if (_ready) return;
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
    _ready = true;
  }

  /// Ao abrir o app: prepara o WorkManager e reagenda a verificação se estava ligada.
  static Future<void> init(Function callbackDispatcher) async {
    if (!supported) return;
    try {
      await Workmanager().initialize(callbackDispatcher);
      await _init();
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kEnabled) ?? false) await _register();
    } catch (e) {
      debugPrint('Avisos: $e');
    }
  }

  /// Liga a verificação em segundo plano (depois do login) e pede a permissão.
  static Future<void> enable() async {
    if (!supported) return;
    try {
      await _init();
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, true);
      await _register();
    } catch (e) {
      debugPrint('Avisos: $e');
    }
  }

  static Future<void> disable() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, false);
      await Workmanager().cancelByUniqueName(task);
    } catch (e) {
      debugPrint('Avisos: $e');
    }
  }

  /// As notificações estão permitidas no Android? (null: não dá para saber)
  static Future<bool?> permitted() async {
    if (!supported) return null;
    try {
      await _init();
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await a?.areNotificationsEnabled();
    } catch (e) {
      return null;
    }
  }

  /// Pede a permissão de novo (Android 13+).
  static Future<void> requestPermission() async {
    if (!supported) return;
    try {
      await _init();
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Avisos: $e');
    }
  }

  /// Notificação de teste (Configurações).
  static Future<void> test(String appName) async {
    final now = DateTime.now().toIso8601String();
    await deliver([Alert('teste:$now', 'Notificação de teste', 'As notificações do $appName estão funcionando.')]);
  }

  static Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  static Future<void> _register() => Workmanager().registerPeriodicTask(
        task,
        task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  /// Mostra as novidades ainda não avisadas e as marca como avisadas.
  ///
  /// [quietKeys]: novidades a marcar como vistas sem notificar (ex.: recados
  /// antigos na primeira verificação de um aparelho novo).
  static Future<void> deliver(List<Alert> alerts, {Set<String> quietKeys = const {}}) async {
    if (alerts.isEmpty && quietKeys.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = {...(prefs.getStringList(_kSeen) ?? const [])};
    final fresh = [for (final a in alerts) if (!seen.contains(a.key)) a];
    seen
      ..addAll(fresh.map((a) => a.key))
      ..addAll(quietKeys);
    final list = seen.toList();
    await prefs.setStringList(_kSeen, list.length > 400 ? list.sublist(list.length - 400) : list);
    if (fresh.isEmpty || !supported) return;
    try {
      await _init();
      for (final a in fresh.take(5)) {
        await _plugin.show(
          id: a.key.hashCode & 0x7fffffff,
          title: a.title,
          body: a.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: channelDescription,
              importance: Importance.high,
              priority: Priority.high,
              color: color,
              styleInformation: BigTextStyleInformation(a.body),
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Avisos: $e');
    }
  }

  /// Primeira verificação neste aparelho: o que já existia não vira notificação.
  static Future<bool> firstRun() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kSeeded) ?? false) return false;
    await prefs.setBool(_kSeeded, true);
    return true;
  }
}
