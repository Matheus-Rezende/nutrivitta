import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// Ponto de entrada da verificação em segundo plano (roda sem a tela do app).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      Background.setup();
      if (!await Alerts.enabled()) return true;
      final session = await Account.background(await SharedPreferences.getInstance());
      if (session == null) return true;
      final (uid, db) = session;
      await Background.check(uid, Remote(db));
    } catch (e) {
      debugPrint('Verificação em segundo plano: $e');
    }
    return true;
  });
}

/// Avisos ao paciente: pedido de conexão de nutricionista e recado novo.
class Background {
  Background._();

  static final instance = Background._();

  static void setup() {
    Alerts.channelId = 'nutricionista';
    Alerts.channelName = 'Nutricionista';
    Alerts.channelDescription = 'Pedidos de conexão e recados do nutricionista';
    Alerts.color = NvColors.green;
  }

  Future<void> init() async {
    setup();
    await Alerts.init(callbackDispatcher);
  }

  Future<void> enable() => Alerts.enable();

  Future<void> disable() => Alerts.disable();

  /// Janela dos recados consultados nas verificações rápidas.
  static DateTime get recentSince => DateTime.now().subtract(const Duration(days: 3));

  static Future<void> check(String uid, Remote remote) async {
    final results = await Future.wait<Object>([
      remote.linksOfPatient(uid),
      remote.recentComments(uid, recentSince),
    ]);
    await report(results[0] as List<Link>, results[1] as Map<String, DayComment>);
  }

  /// Avisa os pedidos pendentes e os recados ainda não avisados.
  static Future<void> report(List<Link> links, Map<String, DayComment> comments) async {
    final linkAlerts = [
      for (final l in links)
        if (l.pending)
          Alert(
            'link:${l.id}:${l.updatedAt}',
            '${l.proName.isEmpty ? 'Um nutricionista' : l.proName} quer acompanhar sua alimentação',
            'Abra o NutriVitta para aceitar ou recusar o pedido.',
          ),
    ];
    final anamnesisAlerts = [
      for (final l in links)
        if (l.anamnesisPending)
          Alert(
            'anam:${l.id}:${l.anamnesisRequestedAt}',
            '${l.proName.isEmpty ? 'Seu nutricionista' : l.proName} pediu para editar sua anamnese',
            'Abra o NutriVitta para permitir ou não.',
          ),
    ];
    final commentAlerts = [
      for (final c in comments.values)
        Alert('comment:${c.date}:${c.updatedAt}', 'Recado de ${c.author.isEmpty ? 'seu nutricionista' : c.author}', c.text),
    ];
    // num aparelho novo, recados antigos não viram notificação
    final first = await Alerts.firstRun();
    await Alerts.deliver(
      [...linkAlerts, ...anamnesisAlerts, if (!first) ...commentAlerts],
      quietKeys: first ? {for (final a in commentAlerts) a.key} : const {},
    );
  }
}
