import 'dart:math';

import '../config.dart';
import '../models/diary.dart';
import 'account.dart';
import 'firebase_rest.dart';

/// Paciente vinculado a um nutricionista.
class PatientLink {
  const PatientLink(this.uid, this.name, this.email);

  final String uid;
  final String name;
  final String email;
}

/// Leitura e gravação dos dados online (Firestore).
///
/// Estrutura:
///   users/{uid}                         perfil + metas
///   users/{uid}/days/{aaaa-mm-dd}       diário do dia
///   users/{uid}/meta/foods|weights      alimentos próprios e pesagens
///   users/{uid}/comments/{aaaa-mm-dd}   recado do nutricionista
///   invites/{código}                    código de convite do nutricionista
///   nutritionists/{uid}/patients/{uid}  pacientes vinculados
class Remote {
  Remote._();

  static final instance = Remote._();

  final _db = Firestore(kFirebaseProjectId, Account.instance.token);

  // ---- conta própria ----

  Future<Map<String, dynamic>?> user(String uid) => _db.get('users/$uid');

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

  Future<Map<String, DayComment>> comments(String uid) async => {
        for (final (id, data) in await _db.list('users/$uid/comments'))
          if (((data['text'] as String?) ?? '').isNotEmpty) id: DayComment.fromJson(id, data),
      };

  // ---- vínculo paciente e nutricionista ----

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Cria o código de convite do nutricionista (uma vez).
  Future<String> createInvite(String uid, Profile p) async {
    final rnd = Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = [for (var i = 0; i < 6; i++) _alphabet[rnd.nextInt(_alphabet.length)]].join();
      if (await _db.get('invites/$code') != null) continue;
      await _db.set('invites/$code', {'uid': uid, 'name': p.name, 'crn': p.crn});
      return code;
    }
    throw StateError('Não foi possível gerar o código de convite.');
  }

  Future<void> updateInvite(String uid, Profile p) async {
    if (p.inviteCode.isEmpty) return;
    await _db.set('invites/${p.inviteCode}', {'uid': uid, 'name': p.name, 'crn': p.crn});
  }

  /// Nutricionista dono do código: (uid, nome), ou null se o código não existe.
  Future<(String, String)?> findInvite(String code) async {
    final j = await _db.get('invites/${code.trim().toUpperCase()}');
    final uid = j?['uid'] as String?;
    if (uid == null || uid.isEmpty) return null;
    return (uid, (j?['name'] as String?) ?? 'Nutricionista');
  }

  /// O paciente autoriza o nutricionista a ver o diário.
  Future<void> link(String patientUid, Profile patient, String nutritionistUid) => _db.set(
      'nutritionists/$nutritionistUid/patients/$patientUid',
      {'name': patient.name, 'email': patient.email, 'linkedAt': DateTime.now().toUtc().toIso8601String()});

  Future<void> unlink(String patientUid, String nutritionistUid) =>
      _db.delete('nutritionists/$nutritionistUid/patients/$patientUid');

  Future<List<PatientLink>> patients(String nutritionistUid) async {
    final list = [
      for (final (id, data) in await _db.list('nutritionists/$nutritionistUid/patients'))
        PatientLink(id, (data['name'] as String?) ?? 'Paciente', (data['email'] as String?) ?? ''),
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // ---- ações do nutricionista sobre o paciente ----

  Future<void> setPatientGoals(String patientUid, Goals g) => saveGoals(patientUid, g);

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
      await _db.set(path, {...c.toJson(), 'updatedAt': DateTime.now().toUtc().toIso8601String()});
    }
  }
}
