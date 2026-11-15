import 'package:nutrivitta_core/nutrivitta_core.dart';

/// Versão do app. Precisa ser igual à do pubspec.yaml (um teste confere).
const kAppVersion = '0.3.0';

const kApp = AppInfo(
  id: 'paciente',
  name: 'NutriVitta',
  version: kAppVersion,
  privacy: 'Seu diário fica salvo no aparelho e, com a conta Google, no banco online do NutriVitta e numa cópia '
      'no seu Google Drive. Só nutricionistas que você aceitou veem seus dados, e você pode desconectar quando quiser.',
);
