import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import 'bspatch.dart';

/// Uma versão publicada.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
    this.manifestUrl,
    this.apkSha256,
    this.patchUrl,
    this.patchSize = 0,
  });

  final String version;
  final String notes;

  /// APK completo (o do processador do aparelho, quando já se sabe qual é).
  final String apkUrl;
  final int apkSize;

  /// update.json da versão: APKs por processador e patches.
  final String? manifestUrl;
  final String? apkSha256;

  /// Patch com só a diferença para o APK instalado, quando existe.
  final String? patchUrl;
  final int patchSize;

  bool get isPatch => patchUrl != null;
  int get downloadSize => isPatch ? patchSize : apkSize;

  String get sizeLabel {
    final mb = downloadSize / 1048576;
    if (mb < 1) return 'menos de 1 MB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  UpdateInfo copyWith({String? apkUrl, int? apkSize, String? apkSha256, String? patchUrl, int? patchSize}) => UpdateInfo(
        version: version,
        notes: notes,
        apkUrl: apkUrl ?? this.apkUrl,
        apkSize: apkSize ?? this.apkSize,
        manifestUrl: manifestUrl,
        apkSha256: apkSha256 ?? this.apkSha256,
        patchUrl: patchUrl ?? this.patchUrl,
        patchSize: patchSize ?? this.patchSize,
      );
}

/// SHA-256 de um arquivo (em outro isolate).
Future<String> _fileSha256(String path) => compute((String p) async {
      final digest = await sha256.bind(File(p).openRead()).first;
      return digest.toString();
    }, path);

/// Monta o APK novo: aplica o patch ao APK instalado e confere o SHA-256.
Future<bool> _buildFromPatch(List<String> a) => compute((List<String> a) async {
      final old = await File(a[0]).readAsBytes();
      final patch = await File(a[1]).readAsBytes();
      final out = bspatch(old, patch);
      if (sha256.convert(out).toString() != a[3]) return false;
      await File(a[2]).writeAsBytes(out, flush: true);
      return true;
    }, a);

/// Compara versões "1.2.3" (ignora o "v" e o "+build"). Negativo se [a] < [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(RegExp(r'\d+').firstMatch(p)?.group(0) ?? '') ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Lê uma Release do GitHub. Só considera versões deste app ([app].id) com APK.
UpdateInfo? parseRelease(Map<String, dynamic> j, AppInfo app) {
  if (j['draft'] == true || j['prerelease'] == true) return null;
  final tag = j['tag_name'] as String?;
  if (tag == null || !tag.startsWith(app.tagPrefix)) return null;
  final version = tag.substring(app.tagPrefix.length);
  final assets = [for (final a in (j['assets'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
  String nameOf(Map m) => (m['name'] ?? '').toString();
  // APK universal (funciona em qualquer aparelho); se não houver, o primeiro APK
  final apks = assets.where((m) => nameOf(m).endsWith('.apk')).toList();
  if (apks.isEmpty) return null;
  final universal = apks.firstWhere((m) => nameOf(m) == app.apkFor(version), orElse: () => apks.first);
  final manifest = assets.where((m) => nameOf(m) == 'update.json').firstOrNull;
  final body = (j['body'] ?? '').toString().replaceAll('\r\n', '\n');
  final notes = body.split(RegExp(r'^## Como instalar', multiLine: true)).first.trim();
  return UpdateInfo(
    version: version,
    notes: notes,
    apkUrl: (universal['browser_download_url'] ?? '').toString(),
    apkSize: (universal['size'] as num?)?.toInt() ?? 0,
    manifestUrl: manifest?['browser_download_url']?.toString(),
  );
}

enum UpdateStage { idle, checking, downloading, installing, failed }

/// Procura, baixa e instala novas versões (Android). No iOS a atualização é
/// pela App Store/TestFlight, então nada aparece.
class Updater extends ChangeNotifier {
  Updater._();

  static final instance = Updater._();

  /// Qual app está rodando (definido ao abrir o app).
  static AppInfo app = const AppInfo(id: 'paciente', name: 'NutriVitta', version: '0.0.0', privacy: '');

  static const _channel = MethodChannel('nutrivitta/updater');
  static const _kLastCheck = 'update_last_check';
  static const _kSnoozed = 'update_snoozed';
  static const _kAuto = 'update_auto_check';

  bool get supported => !kIsWeb && Platform.isAndroid;

  UpdateInfo? available;
  UpdateStage stage = UpdateStage.idle;
  double? progress;
  String? message;
  DateTime? lastCheck;
  bool autoCheck = true;

  /// O último download (ou a instalação) não terminou.
  bool downloadFailed = false;

  /// A janela da atualização está aberta (então o aviso flutuante some).
  bool sheetOpen = false;

  void setSheetOpen(bool v) {
    if (sheetOpen == v) return;
    sheetOpen = v;
    notifyListeners();
  }

  /// Há um download ou instalação em andamento.
  bool get busy => stage == UpdateStage.downloading || stage == UpdateStage.installing;
  bool _loaded = false;

  Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    if (!_loaded) {
      _loaded = true;
      final t = p.getString(_kLastCheck);
      lastCheck = t == null ? null : DateTime.tryParse(t);
      autoCheck = p.getBool(_kAuto) ?? true;
    }
    return p;
  }

  Future<void> setAutoCheck(bool v) async {
    final p = await _prefs();
    autoCheck = v;
    await p.setBool(_kAuto, v);
    notifyListeners();
  }

  /// Procura uma versão nova. Sem [force], respeita o intervalo de 6 horas e a
  /// opção de verificar sozinho. Retorna a versão nova, se houver.
  Future<UpdateInfo?> check({bool force = false}) async {
    if (!supported || stage == UpdateStage.checking || stage == UpdateStage.downloading) return available;
    final p = await _prefs();
    if (!force) {
      if (!autoCheck) return available;
      if (lastCheck != null && DateTime.now().difference(lastCheck!) < const Duration(hours: 6)) return available;
    }
    stage = UpdateStage.checking;
    message = null;
    notifyListeners();
    try {
      final info = await _fetchLatest();
      lastCheck = DateTime.now();
      await p.setString(_kLastCheck, lastCheck!.toIso8601String());
      available = info != null && compareVersions(info.version, app.version) > 0 ? await _plan(info) : null;
      stage = UpdateStage.idle;
    } catch (e) {
      stage = force ? UpdateStage.failed : UpdateStage.idle;
      message = 'Não foi possível procurar atualizações. Confira a internet e tente de novo.';
    }
    notifyListeners();
    return available;
  }

  /// O aviso automático foi adiado para esta versão nos últimos 2 dias?
  Future<bool> isSnoozed(UpdateInfo u) async {
    final p = await _prefs();
    final s = p.getString(_kSnoozed);
    if (s == null) return false;
    final parts = s.split('|');
    final t = parts.length > 1 ? DateTime.tryParse(parts[1]) : null;
    return parts.first == u.version && t != null && DateTime.now().difference(t) < const Duration(days: 2);
  }

  Future<void> snooze(UpdateInfo u) async {
    final p = await _prefs();
    await p.setString(_kSnoozed, '${u.version}|${DateTime.now().toIso8601String()}');
  }

  /// Os dois apps publicam no mesmo repositório: procura a versão mais nova
  /// com a tag deste app (paciente-v... ou pro-v...).
  Future<UpdateInfo?> _fetchLatest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/${AppInfo.repo}/releases?per_page=30'));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, app.userAgent);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      UpdateInfo? best;
      for (final r in jsonDecode(text) as List) {
        final info = parseRelease(Map<String, dynamic>.from(r as Map), app);
        if (info != null && (best == null || compareVersions(info.version, best.version) > 0)) best = info;
      }
      return best;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _get(HttpClient client, String url) async {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, app.userAgent);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    return text;
  }

  /// Escolhe o que baixar: o APK do processador do aparelho e, se houver, o
  /// patch com só a diferença para o APK instalado.
  Future<UpdateInfo> _plan(UpdateInfo info) async {
    final url = info.manifestUrl;
    if (url == null) return info;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final m = Map<String, dynamic>.from(jsonDecode(await _get(client, url)) as Map);
      final apks = Map<String, dynamic>.from(m['apks'] as Map? ?? const {});
      final abis = (await _channel.invokeListMethod<String>('abis')) ?? const <String>[];
      final abi = abis.firstWhere((a) => apks.containsKey(a), orElse: () => 'universal');
      final full = apks[abi] is Map ? Map<String, dynamic>.from(apks[abi] as Map) : null;
      if (full == null) return info;
      final base = 'https://github.com/${AppInfo.repo}/releases/download/${app.tagFor(info.version)}/';
      var plan = info.copyWith(
        apkUrl: '$base${full['name']}',
        apkSize: (full['size'] as num).toInt(),
        apkSha256: full['sha256'] as String?,
      );
      final mine = await _installedSha();
      if (mine == null) return plan;
      for (final p in (m['patches'] as List? ?? const [])) {
        final pm = Map<String, dynamic>.from(p as Map);
        if (pm['fromSha256'] == mine && pm['to'] == abi) {
          plan = plan.copyWith(patchUrl: '$base${pm['name']}', patchSize: (pm['size'] as num).toInt());
          break;
        }
      }
      return plan;
    } catch (e) {
      debugPrint('Atualização parcial indisponível: $e');
      return info;
    } finally {
      client.close(force: true);
    }
  }

  /// SHA-256 do APK instalado (guardado para não recalcular a cada verificação).
  Future<String?> _installedSha() async {
    final path = await _channel.invokeMethod<String>('apkPath');
    if (path == null) return null;
    final f = File(path);
    final st = f.statSync();
    final key = '$path|${st.size}|${st.modified.millisecondsSinceEpoch}';
    final p = await _prefs();
    final cached = p.getString('update_apk_sha');
    if (cached != null && cached.startsWith('$key=')) return cached.substring(key.length + 1);
    final sha = await _fileSha256(path);
    await p.setString('update_apk_sha', '$key=$sha');
    return sha;
  }

  /// Baixa [url] para [file], mostrando o progresso.
  Future<void> _download(HttpClient client, String url, File file, int expected) async {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, app.userAgent);
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final total = res.contentLength > 0 ? res.contentLength : expected;
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in res) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) {
        final p = got / total;
        if (progress == null || p - progress! >= 0.01 || p >= 1) {
          progress = p;
          notifyListeners();
        }
      }
    }
    await sink.close();
  }

  /// Baixa o APK (mostrando o progresso) e abre o instalador do Android.
  Future<void> downloadAndInstall() async {
    final u = available;
    if (u == null || !supported) return;
    if (stage == UpdateStage.downloading) return;
    stage = UpdateStage.downloading;
    progress = 0;
    message = null;
    downloadFailed = false;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final dir = await _channel.invokeMethod<String>('updatesDir');
      final file = File('$dir/${app.apkFor(u.version)}');
      final complete = file.existsSync() && u.apkSize > 0 && file.lengthSync() == u.apkSize;
      if (!complete) {
        for (final old in Directory(dir!).listSync()) {
          if (old is File) old.deleteSync();
        }
        var built = false;
        final patchUrl = u.patchUrl, target = u.apkSha256;
        if (patchUrl != null && target != null) {
          // só a diferença: baixa o patch e monta o APK novo a partir do instalado
          try {
            final patch = File('$dir/update.patch');
            await _download(client, patchUrl, patch, u.patchSize);
            final installed = await _channel.invokeMethod<String>('apkPath');
            built = installed != null && await _buildFromPatch([installed, patch.path, file.path, target]);
            if (patch.existsSync()) patch.deleteSync();
          } catch (e) {
            debugPrint('Patch falhou, baixando o APK completo: $e');
            built = false;
          }
          if (!built && file.existsSync()) file.deleteSync();
          progress = 0;
          notifyListeners();
        }
        if (!built) await _download(client, u.apkUrl, file, u.apkSize);
      }
      progress = 1;
      await install(file.path);
    } catch (e) {
      stage = UpdateStage.failed;
      downloadFailed = true;
      message = 'O download não terminou. Confira a internet e tente de novo.';
      notifyListeners();
    } finally {
      client.close(force: true);
    }
  }

  /// Abre o instalador. Se faltar a permissão de instalar apps, abre a tela
  /// de configurações do Android para a pessoa liberar.
  Future<void> install(String path) async {
    stage = UpdateStage.installing;
    notifyListeners();
    final r = await _channel.invokeMethod<String>('install', {'path': path});
    if (r == 'needs_permission') {
      stage = UpdateStage.failed;
      downloadFailed = true;
      message = 'Libere "Permitir desta fonte" para o ${app.name} na tela que abriu, volte e toque em '
          '"Atualizar agora" de novo.';
    } else {
      stage = UpdateStage.idle;
    }
    notifyListeners();
  }
}
