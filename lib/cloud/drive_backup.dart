import 'dart:convert';

import 'package:http/http.dart' as http;

/// Acesso ao backup no Google Drive, na pasta escondida do app
/// ("appDataFolder"): só o NutriVitta enxerga esse arquivo, ele não aparece
/// no Drive da pessoa e não ocupa espaço de outros apps.
class DriveBackup {
  DriveBackup(this.headers, {http.Client? client}) : _client = client ?? http.Client();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const fileName = 'nutrivitta_backup.json';

  final Map<String, String> headers;
  final http.Client _client;

  static final _api = Uri.parse('https://www.googleapis.com/drive/v3/files');
  static const _timeout = Duration(seconds: 30);

  /// Arquivo de backup existente: (id, data da última alteração).
  Future<(String, DateTime?)?> find() async {
    final uri = _api.replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name = '$fileName' and trashed = false",
      'fields': 'files(id,modifiedTime)',
      'orderBy': 'modifiedTime desc',
      'pageSize': '1',
    });
    final r = await _client.get(uri, headers: headers).timeout(_timeout);
    _check(r);
    final files = (jsonDecode(r.body) as Map)['files'] as List? ?? const [];
    if (files.isEmpty) return null;
    final f = Map<String, dynamic>.from(files.first as Map);
    return (f['id'] as String, DateTime.tryParse((f['modifiedTime'] as String?) ?? ''));
  }

  /// Conteúdo do backup, ou null se ainda não existe.
  Future<Map<String, dynamic>?> download() async {
    final f = await find();
    if (f == null) return null;
    final r = await _client.get(_api.replace(path: '${_api.path}/${f.$1}', queryParameters: {'alt': 'media'}),
        headers: headers);
    _check(r);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
  }

  /// Grava o backup (cria o arquivo na primeira vez).
  Future<void> upload(Map<String, dynamic> backup) async {
    final f = await find();
    const boundary = 'nutrivitta_backup_boundary';
    final meta = f == null ? {'name': fileName, 'parents': ['appDataFolder']} : <String, Object>{};
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(meta)}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(backup)}\r\n'
        '--$boundary--';
    final h = {...headers, 'Content-Type': 'multipart/related; boundary=$boundary'};
    final upload = Uri.parse('https://www.googleapis.com/upload/drive/v3/files');
    final http.Response r;
    if (f == null) {
      r = await _client.post(upload.replace(queryParameters: {'uploadType': 'multipart'}),
          headers: h, body: utf8.encode(body));
    } else {
      r = await _client.patch(upload.replace(path: '${upload.path}/${f.$1}', queryParameters: {'uploadType': 'multipart'}),
          headers: h, body: utf8.encode(body));
    }
    _check(r);
  }

  /// Apaga o backup da nuvem.
  Future<void> delete() async {
    final f = await find();
    if (f == null) return;
    final r = await _client.delete(_api.replace(path: '${_api.path}/${f.$1}'), headers: headers);
    if (r.statusCode != 404) _check(r);
  }

  static void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw DriveException(r.statusCode, r.body.length > 300 ? r.body.substring(0, 300) : r.body);
  }
}

class DriveException implements Exception {
  DriveException(this.status, this.body);

  final int status;
  final String body;

  bool get unauthorized => status == 401 || status == 403;

  @override
  String toString() => 'Drive respondeu $status: $body';
}
