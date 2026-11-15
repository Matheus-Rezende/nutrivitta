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
      ProAlerts.setup();
      if (!await Alerts.enabled()) return true;
      final session = await Account.background(await SharedPreferences.getInstance());
      if (session == null) return true;
      final (uid, db) = session;
      await ProAlerts.report(await Remote(db).linksOfPro(uid));
    } catch (e) {
      debugPrint('Verificação em segundo plano: $e');
    }
    return true;
  });
}

/// Avisos ao nutricionista: o paciente aceitou ou recusou o pedido.
class ProAlerts {
  ProAlerts._();

  static void setup() {
    Alerts.channelId = 'pacientes';
    Alerts.channelName = 'Pacientes';
    Alerts.channelDescription = 'Respostas dos pacientes aos pedidos de conexão';
    Alerts.color = NvColors.teal;
  }

  static Future<void> init() async {
    setup();
    await Alerts.init(callbackDispatcher);
  }

  static Future<void> enable() => Alerts.enable();

  static Future<void> report(List<Link> links) async {
    final alerts = [
      for (final l in links)
        if (l.status == LinkStatus.accepted || l.status == LinkStatus.declined || l.status == LinkStatus.ended)
          Alert(
            'link:${l.id}:${l.status.name}:${l.updatedAt}',
            switch (l.status) {
              LinkStatus.accepted => '${l.patientLabel} aceitou seu pedido',
              LinkStatus.declined => '${l.patientLabel} recusou seu pedido',
              _ => '${l.patientLabel} encerrou a conexão',
            },
            l.accepted ? 'Abra o NutriVitta Pro para acompanhar a alimentação.' : 'A conexão não está ativa.',
          ),
    ];
    // na primeira verificação do aparelho, o que já existia não vira notificação
    final first = await Alerts.firstRun();
    await Alerts.deliver(first ? const [] : alerts, quietKeys: first ? {for (final a in alerts) a.key} : const {});
  }
}
