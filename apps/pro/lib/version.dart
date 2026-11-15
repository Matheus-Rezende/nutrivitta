import 'package:nutrivitta_core/nutrivitta_core.dart';

/// Versão do app. Precisa ser igual à do pubspec.yaml (um teste confere).
const kAppVersion = '0.5.1';

const kApp = AppInfo(
  id: 'pro',
  name: 'NutriVitta Pro',
  version: kAppVersion,
  pro: true,
  privacy: 'Você só vê os dados de pacientes que aceitaram o seu pedido de conexão, e o acesso termina quando '
      'o paciente desconecta. Os dados de alimentação e saúde são sensíveis (LGPD): use-os só para o acompanhamento.',
);
