import 'dart:convert';

import 'package:http/http.dart' as http;

/// Firebase pela API REST: login (Identity Toolkit) e banco (Firestore).
/// Usa só o pacote http, sem plugins nativos nem google-services.json.

const _timeout = Duration(seconds: 25);

class CloudException implements Exception {
  CloudException(this.status, this.body);

  final int status;
  final String body;

  bool get unauthorized => status == 401;
  bool get denied => status == 403;
  bool get notFound => status == 404;

  @override
  String toString() => 'Nuvem respondeu $status: ${body.length > 300 ? body.substring(0, 300) : body}';
}

void _check(http.Response r) {
  if (r.statusCode >= 200 && r.statusCode < 300) return;
  throw CloudException(r.statusCode, r.body);
}

/// Sessão do Firebase Authentication.
class FirebaseSession {
  FirebaseSession(this.uid, this.idToken, this.refreshToken, this.expires);

  final String uid;
  final String idToken;
  final String refreshToken;
  final DateTime expires;

  bool get valid => DateTime.now().isBefore(expires);
}

class FirebaseAuthRest {
  FirebaseAuthRest(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static DateTime _expiry(Object? seconds) {
    final s = int.tryParse('$seconds') ?? 3600;
    return DateTime.now().add(Duration(seconds: s - 120));
  }

  /// Troca o token de identidade do Google por uma sessão do Firebase.
  Future<FirebaseSession> signInWithGoogle(String googleIdToken) async {
    final uri = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp')
        .replace(queryParameters: {'key': apiKey});
    final r = await _client
        .post(uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'postBody': 'id_token=${Uri.encodeQueryComponent(googleIdToken)}&providerId=google.com',
              'requestUri': 'http://localhost',
              'returnSecureToken': true,
              'returnIdpCredential': true,
            }))
        .timeout(_timeout);
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return FirebaseSession(
        j['localId'] as String, j['idToken'] as String, j['refreshToken'] as String, _expiry(j['expiresIn']));
  }

  /// Renova a sessão (o token dura cerca de uma hora).
  Future<FirebaseSession> refresh(FirebaseSession old) async {
    final uri = Uri.parse('https://securetoken.googleapis.com/v1/token').replace(queryParameters: {'key': apiKey});
    final r = await _client
        .post(uri,
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(old.refreshToken)}')
        .timeout(_timeout);
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return FirebaseSession(
        j['user_id'] as String, j['id_token'] as String, j['refresh_token'] as String, _expiry(j['expires_in']));
  }
}

/// Converte valores do Dart para o formato do Firestore.
Map<String, dynamic> toValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is List) {
    return {
      'arrayValue': {'values': [for (final e in v) toValue(e)]}
    };
  }
  if (v is Map) {
    return {
      'mapValue': {'fields': toFields(v)}
    };
  }
  return {'stringValue': '$v'};
}

Map<String, dynamic> toFields(Map<dynamic, dynamic> data) => {for (final e in data.entries) '${e.key}': toValue(e.value)};

Object? fromValue(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'] as String;
  if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}') ?? 0;
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
  if (v.containsKey('timestampValue')) return v['timestampValue'] as String;
  if (v.containsKey('arrayValue')) {
    final values = (v['arrayValue'] as Map)['values'] as List? ?? const [];
    return [for (final e in values) fromValue(Map<String, dynamic>.from(e as Map))];
  }
  if (v.containsKey('mapValue')) {
    return fromFields((v['mapValue'] as Map)['fields'] as Map?);
  }
  return null;
}

Map<String, dynamic> fromFields(Map<dynamic, dynamic>? fields) => {
      for (final e in (fields ?? const {}).entries) '${e.key}': fromValue(Map<String, dynamic>.from(e.value as Map)),
    };

/// Cliente mínimo do Cloud Firestore.
class Firestore {
  Firestore(this.projectId, this.token, {http.Client? client}) : _client = client ?? http.Client();

  final String projectId;

  /// Devolve o token da sessão (renovado quando preciso).
  final Future<String?> Function() token;
  final http.Client _client;

  Uri _doc(String path, [Map<String, dynamic>? query]) => Uri.https(
      'firestore.googleapis.com', '/v1/projects/$projectId/databases/(default)/documents/$path', query);

  Future<Map<String, String>> _headers() async {
    final t = await token();
    if (t == null) throw CloudException(401, 'Sem sessão');
    return {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'};
  }

  /// Lê um documento; null se não existe.
  Future<Map<String, dynamic>?> get(String path) async {
    final r = await _client.get(_doc(path), headers: await _headers()).timeout(_timeout);
    if (r.statusCode == 404) return null;
    _check(r);
    return fromFields((jsonDecode(utf8.decode(r.bodyBytes)) as Map)['fields'] as Map?);
  }

  /// Grava um documento. Com [mask], só os campos listados são alterados.
  Future<void> set(String path, Map<String, dynamic> data, {List<String>? mask}) async {
    final uri = _doc(path, mask == null ? null : {'updateMask.fieldPaths': mask});
    final r = await _client
        .patch(uri, headers: await _headers(), body: jsonEncode({'fields': toFields(data)}))
        .timeout(_timeout);
    _check(r);
  }

  Future<void> delete(String path) async {
    final r = await _client.delete(_doc(path), headers: await _headers()).timeout(_timeout);
    if (r.statusCode != 404) _check(r);
  }

  /// Todos os documentos de uma coleção: (id, dados).
  Future<List<(String, Map<String, dynamic>)>> list(String collection) async {
    final out = <(String, Map<String, dynamic>)>[];
    String? page;
    do {
      final uri = _doc(collection, {'pageSize': '300', if (page != null) 'pageToken': page});
      final r = await _client.get(uri, headers: await _headers()).timeout(_timeout);
      _check(r);
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      for (final d in (j['documents'] as List? ?? const [])) {
        final doc = Map<String, dynamic>.from(d as Map);
        final name = doc['name'] as String;
        out.add((name.substring(name.lastIndexOf('/') + 1), fromFields(doc['fields'] as Map?)));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return out;
  }
}
