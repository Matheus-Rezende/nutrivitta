/// Identidade de cada app (NutriVitta ou NutriVitta Pro), usada pelas
/// atualizações e pela tela de Configurações.
class AppInfo {
  const AppInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.privacy,
    this.pro = false,
  });

  /// 'paciente' ou 'pro': prefixo das tags (paciente-v0.3.0) e dos APKs.
  final String id;
  final String name;

  /// Versão instalada; igual à do pubspec.yaml (um teste confere).
  final String version;

  /// Texto da seção Privacidade.
  final String privacy;
  final bool pro;

  /// Repositório onde as versões são publicadas (página de Releases).
  static const repo = 'Matheus-Rezende/nutrivitta';

  String get tagPrefix => '$id-v';
  String tagFor(String v) => '$tagPrefix$v';
  String apkFor(String v, [String? abi]) => 'nutrivitta-$id-v$v${abi == null ? '' : '-$abi'}.apk';
  String get userAgent => 'NutriVitta-$id/$version';
}
