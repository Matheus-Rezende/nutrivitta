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
///   users/{uid}/photos/{registro}        foto da refeição (JPEG em base64)
///   users/{uid}/comments/{aaaa-mm-dd}    recado do nutricionista
///   directory/{e-mail}                   e-mail do paciente -> uid
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

  // ---- diretório (encontrar o paciente pelo e-mail) ----

  static String emailKey(String email) => email.trim().toLowerCase();

  Future<void> publishDirectory(String uid, String email, String name) =>
      _db.set('directory/${emailKey(email)}', {'uid': uid, 'name': name});

  /// Paciente com este e-mail: (uid, nome), ou null se não usa o app.
  Future<(String, String)?> findPatient(String email) async {
    final j = await _db.get('directory/${emailKey(email)}');
    final uid = j?['uid'] as String?;
    if (uid == null || uid.isEmpty) return null;
    return (uid, (j?['name'] as String?) ?? '');
  }

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
}
