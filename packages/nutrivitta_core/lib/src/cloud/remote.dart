import 'dart:math';

import '../config.dart';
import '../models/diary.dart';
import '../models/link.dart';
import '../models/patient.dart';
import 'account.dart';
import 'firebase_rest.dart';

/// Leitura e gravação dos dados online (Firestore), usadas pelos dois apps.
///
/// Estrutura:
///   users/{uid}                          perfil do paciente + metas
///   users/{uid}/days/{aaaa-mm-dd}        diário do dia
///   users/{uid}/meta/foods|weights       alimentos próprios e pesagens
///   users/{uid}/meta/anamnesis|measures  anamnese e medidas corporais
///   users/{uid}/photos/{dia_refeição}    foto do prato de cada refeição (JPEG em base64)
///   users/{uid}/comments/{aaaa-mm-dd}    recado do nutricionista
///   codes/{código}                       código do paciente -> uid e nome
///   pros/{uid}                           perfil do nutricionista
///   links/{proUid}_{patientUid}          pedido de conexão / vínculo
class Remote {
  Remote(this._db);

  static final instance = Remote(Firestore(kFirebaseProjectId, Account.instance.token));

  final Firestore _db;

  // ---- paciente ----

  Future<Map<String, dynamic>?> user(String uid) => _db.get('users/$uid');

  Future<Profile?> profile(String uid) async {
    final j = await user(uid);
    return j == null ? null : Profile.fromJson(j);
  }

  Future<void> saveProfile(String uid, Profile p) => _db.set('users/$uid', p.toJson(), mask: Profile.fields);

  Future<void> saveGoals(String uid, Goals g) => _db.set('users/$uid', {'goals': g.toJson()}, mask: const ['goals']);

  Future<void> saveDay(String uid, DayLog day) => _db.set('users/$uid/days/${day.date}', day.toJson());

  Future<DayLog?> day(String uid, String date) async {
    final j = await _db.get('users/$uid/days/$date');
    return j == null ? null : DayLog.fromJson(date, j);
  }

  /// Vários dias de uma vez (dias sem registro ficam de fora).
  Future<Map<String, DayLog>> days(String uid, List<String> dates) async {
    final found = await Future.wait([for (final d in dates) day(uid, d)]);
    return {
      for (final d in found)
        if (d != null) d.date: d,
    };
  }

  Future<List<DayLog>> allDays(String uid) async =>
      [for (final (id, data) in await _db.list('users/$uid/days')) DayLog.fromJson(id, data)];

  Future<void> saveMeta(String uid, String name, List<Map<String, dynamic>> items) =>
      _db.set('users/$uid/meta/$name', {'items': items});

  Future<List<Map<String, dynamic>>> meta(String uid, String name) async {
    final j = await _db.get('users/$uid/meta/$name');
    return [for (final e in (j?['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
  }

  Future<List<WeightRecord>> weights(String uid) async =>
      [for (final w in await meta(uid, 'weights')) WeightRecord.fromJson(w)];

  Future<List<BodyMeasure>> measures(String uid) async =>
      [for (final m in await meta(uid, 'measures')) BodyMeasure.fromJson(m)]..sort((a, b) => a.date.compareTo(b.date));

  Future<void> saveMeasures(String uid, List<BodyMeasure> list) =>
      saveMeta(uid, 'measures', [for (final m in list) m.toJson()]);

  Future<Anamnesis> anamnesis(String uid) async => Anamnesis.fromJson(await _db.get('users/$uid/meta/anamnesis'));

  Future<void> saveAnamnesis(String uid, Anamnesis a) => _db.set('users/$uid/meta/anamnesis', a.toJson());

  // ---- fotos ----

  Future<String?> photo(String uid, String entryId) async {
    final j = await _db.get('users/$uid/photos/$entryId');
    final data = j?['data'];
    return data is String && data.isNotEmpty ? data : null;
  }

  Future<void> savePhoto(String uid, String entryId, String date, String base64Jpeg) =>
      _db.set('users/$uid/photos/$entryId', {'data': base64Jpeg, 'date': date, 'mime': 'image/jpeg'});

  Future<void> deletePhoto(String uid, String entryId) => _db.delete('users/$uid/photos/$entryId');

  // ---- recados ----

  Future<Map<String, DayComment>> comments(String uid) async => {
        for (final (id, data) in await _db.list('users/$uid/comments'))
          if (((data['text'] as String?) ?? '').isNotEmpty) id: DayComment.fromJson(id, data),
      };

  /// Recados criados ou editados desde [since] (consulta leve, para avisos).
  Future<Map<String, DayComment>> recentComments(String uid, DateTime since) async => {
        for (final (id, data) in await _db.where('comments', 'updatedAt', since.toUtc().toIso8601String(),
            parent: 'users/$uid', op: 'GREATER_THAN_OR_EQUAL'))
          if (((data['text'] as String?) ?? '').isNotEmpty) id: DayComment.fromJson(id, data),
      };

  Future<DayComment?> comment(String patientUid, String date) async {
    final j = await _db.get('users/$patientUid/comments/$date');
    if (j == null || ((j['text'] as String?) ?? '').isEmpty) return null;
    return DayComment.fromJson(date, j);
  }

  Future<void> setComment(String patientUid, DayComment c) async {
    final path = 'users/$patientUid/comments/${c.date}';
    if (c.text.trim().isEmpty) {
      await _db.delete(path);
    } else {
      await _db.set(path, c.toJson());
    }
  }

  /// O paciente apaga um recado do nutricionista.
  Future<void> deleteComment(String patientUid, String date) => _db.delete('users/$patientUid/comments/$date');

  // ---- código do paciente (o nutricionista encontra o paciente por ele) ----

  /// Letras e números sem os que se confundem (0/O, 1/I/L).
  static const codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const codeLength = 8;

  /// Deixa o código só com letras e números, em maiúsculas.
  static String normalizeCode(String code) => code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Mostra o código em dois blocos (ABCD-1234).
  static String formatCode(String code) {
    final c = normalizeCode(code);
    return c.length == codeLength ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
  }

  /// Cria um código novo e livre para o paciente.
  Future<String> claimCode(String uid, String name) async {
    final rnd = Random.secure();
    for (var attempt = 0; attempt < 6; attempt++) {
      final code = [for (var i = 0; i < codeLength; i++) codeAlphabet[rnd.nextInt(codeAlphabet.length)]].join();
      if (await _db.get('codes/$code') != null) continue;
      await _db.set('codes/$code', {'uid': uid, 'name': name, 'createdAt': DateTime.now().toUtc().toIso8601String()});
      return code;
    }
    throw StateError('Não foi possível gerar o código.');
  }

  /// Atualiza o nome mostrado ao nutricionista junto com o código.
  Future<void> renameCode(String uid, String code, String name) =>
      _db.set('codes/$code', {'uid': uid, 'name': name}, mask: const ['uid', 'name']);

  Future<void> releaseCode(String code) => _db.delete('codes/$code');

  /// Paciente dono do código: (uid, nome), ou null se o código não existe.
  Future<(String, String)?> findPatientByCode(String code) async {
    final c = normalizeCode(code);
    if (c.length != codeLength) return null;
    final j = await _db.get('codes/$c');
    final uid = j?['uid'] as String?;
    if (uid == null || uid.isEmpty) return null;
    return (uid, (j?['name'] as String?) ?? '');
  }

  /// Apaga o registro antigo por e-mail (versões até a 0.4.0).
  Future<void> deleteDirectory(String email) => _db.delete('directory/${email.trim().toLowerCase()}');

  // ---- nutricionista ----

  Future<ProProfile?> pro(String uid) async {
    final j = await _db.get('pros/$uid');
    return j == null ? null : ProProfile.fromJson(j);
  }

  Future<void> savePro(String uid, ProProfile p) => _db.set('pros/$uid', p.toJson());

  // ---- vínculos ----

  Future<List<Link>> linksOfPro(String proUid) async =>
      [for (final (_, data) in await _db.where('links', 'proUid', proUid)) Link.fromJson(data)];

  Future<List<Link>> linksOfPatient(String patientUid) async =>
      [for (final (_, data) in await _db.where('links', 'patientUid', patientUid)) Link.fromJson(data)];

  Future<void> saveLink(Link l) => _db.set('links/${l.id}', l.toJson());

  /// O paciente responde: só o campo status (e a data) mudam.
  Future<void> answerLink(Link l, LinkStatus status) => _db.set(
      'links/${l.id}', {'status': status.name, 'updatedAt': DateTime.now().toUtc().toIso8601String()},
      mask: const ['status', 'updatedAt']);

  Future<void> deleteLink(Link l) => _db.delete('links/${l.id}');

  /// Grava só alguns campos do vínculo (os outros ficam como estão).
  Future<void> updateLink(Link l, Map<String, dynamic> fields) =>
      _db.set('links/${l.id}', fields, mask: fields.keys.toList());
}
