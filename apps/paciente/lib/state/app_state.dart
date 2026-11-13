import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado do app: tabela de alimentos (assets) e os dados da pessoa, sempre
/// gravados primeiro no aparelho. A nuvem é sincronizada por cima (ver Sync).
class AppState extends ChangeNotifier {
  AppState._(this._prefs, this.foodDb);

  static const _kProfile = 'nv_profile_v1';
  static const _kGoals = 'nv_goals_v1';
  static const _kFoods = 'nv_foods_v1';
  static const _kWeights = 'nv_weights_v1';
  static const _kComments = 'nv_comments_v1';
  static const _kDirty = 'nv_dirty_v1';
  static const _kOwner = 'nv_owner_v1';
  static const _kOnboarded = 'nv_onboarded_v1';
  static const _kAnamnesis = 'nv_anamnesis_v1';
  static const _kMeasures = 'nv_measures_v1';
  static const _kLinks = 'nv_links_v1';
  static const _kDayPrefix = 'nv_day_';
  static const _kPhotoPrefix = 'nv_photo_';

  // marcas de "falta enviar para a nuvem"
  static const dirtyProfile = 'profile';
  static const dirtyGoals = 'goals';
  static const dirtyFoods = 'foods';
  static const dirtyWeights = 'weights';
  static const dirtyAnamnesis = 'anamnesis';
  static const dirtyMeasures = 'measures';
  static String dirtyDay(String date) => 'day:$date';
  static String dirtyPhoto(String id) => 'photo:$id';
  static String dirtyPhotoDelete(String id) => 'photodel:$id';

  final SharedPreferences _prefs;
  final FoodDb foodDb;

  /// Chamado depois de cada gravação local (a sincronização se agenda aqui).
  VoidCallback? onSaved;

  Profile _profile = const Profile();
  Goals _goals = const Goals();
  bool _onboarded = false;
  String? _owner;
  final Map<String, DayLog> _days = {};
  List<Food> _customFoods = [];
  List<WeightRecord> _weights = [];
  Map<String, DayComment> _comments = {};
  Anamnesis _anamnesis = const Anamnesis();
  List<BodyMeasure> _measures = [];
  List<Link> _links = [];
  Set<String> _dirty = {};

  /// A pessoa escolheu usar sem conta (só neste aparelho).
  bool localMode = false;

  void useLocalMode() {
    localMode = true;
    notifyListeners();
  }

  static Future<AppState> load() async {
    final results = await Future.wait<Object>([FoodDb.load(), SharedPreferences.getInstance()]);
    final state = AppState._(results[1] as SharedPreferences, results[0] as FoodDb);
    state._read();
    return state;
  }

  Map<String, dynamic>? _json(String key) {
    final s = _prefs.getString(key);
    if (s == null || s.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _jsonList(String key) {
    final s = _prefs.getString(key);
    if (s == null || s.isEmpty) return const [];
    try {
      return [for (final e in jsonDecode(s) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return const [];
    }
  }

  void _read() {
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _owner = _prefs.getString(_kOwner);
    final p = _json(_kProfile);
    if (p != null) _profile = Profile.fromJson(p);
    final g = _json(_kGoals);
    if (g != null) _goals = Goals.fromJson(g);
    _customFoods = [for (final f in _jsonList(_kFoods)) Food.fromJson(f)];
    _weights = [for (final w in _jsonList(_kWeights)) WeightRecord.fromJson(w)];
    final c = _json(_kComments) ?? const {};
    _comments = {
      for (final e in c.entries) e.key: DayComment.fromJson(e.key, Map<String, dynamic>.from(e.value as Map)),
    };
    _anamnesis = Anamnesis.fromJson(_json(_kAnamnesis));
    _measures = [for (final m in _jsonList(_kMeasures)) BodyMeasure.fromJson(m)];
    _links = [for (final l in _jsonList(_kLinks)) Link.fromJson(l)];
    _dirty = (_prefs.getStringList(_kDirty) ?? const []).toSet();
    _days.clear();
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_kDayPrefix)) continue;
      final date = key.substring(_kDayPrefix.length);
      final j = _json(key);
      if (j != null) _days[date] = DayLog.fromJson(date, j);
    }
  }

  // ---- leitura ----

  Profile get profile => _profile;
  Goals get goals => _goals;
  bool get onboarded => _onboarded;
  String? get owner => _owner;
  List<Food> get customFoods => List.unmodifiable(_customFoods);
  List<WeightRecord> get weights => List.unmodifiable(_weights);
  Set<String> get dirty => Set.unmodifiable(_dirty);
  Map<String, DayLog> get days => Map.unmodifiable(_days);

  DayLog day(String date) => _days[date] ?? DayLog(date);

  DayComment? comment(String date) => _comments[date];

  Map<String, DayComment> get comments => Map.unmodifiable(_comments);
  Anamnesis get anamnesis => _anamnesis;
  List<BodyMeasure> get measures => List.unmodifiable(_measures);

  /// Pedidos e vínculos com nutricionistas (cópia do que está online).
  List<Link> get links => List.unmodifiable(_links);
  List<Link> get pendingLinks => _links.where((l) => l.pending).toList();
  List<Link> get connectedLinks =>
      _links.where((l) => l.accepted && _profile.nutritionistUids.contains(l.proUid)).toList();

  /// Foto ainda não enviada (base64), guardada no aparelho até subir.
  String? localPhoto(String entryId) => _prefs.getString('$_kPhotoPrefix$entryId');

  Food? food(String id) => foodDb.byId(id, extra: _customFoods);

  List<Food> search(String query) => foodDb.search(query, extra: _customFoods);

  /// Alimentos usados recentemente, sem repetir.
  List<Food> recentFoods({int limit = 20}) {
    final entries = [for (final d in _days.values) ...d.entries]..sort((a, b) => b.time.compareTo(a.time));
    final seen = <String>{};
    final out = <Food>[];
    for (final e in entries) {
      if (e.foodId.isEmpty || !seen.add(e.foodId)) continue;
      final f = food(e.foodId);
      if (f != null) out.add(f);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ---- gravação ----

  final _rnd = Random();

  String newId() => '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';

  void _mark(String what) {
    _dirty.add(what);
    _prefs.setStringList(_kDirty, _dirty.toList());
  }

  void clearDirty(String what) {
    if (_dirty.remove(what)) _prefs.setStringList(_kDirty, _dirty.toList());
  }

  void _changed() {
    notifyListeners();
    onSaved?.call();
  }

  void _saveDay(DayLog d) {
    d.updatedAt = DateTime.now().toUtc();
    _days[d.date] = d;
    _prefs.setString('$_kDayPrefix${d.date}', jsonEncode(d.toJson()));
    _mark(dirtyDay(d.date));
    _changed();
  }

  /// Registra um alimento no dia em que foi consumido.
  void addEntry(FoodEntry e) {
    final d = day(dateKey(e.time));
    d.entries.add(e);
    _saveDay(d);
  }

  /// Troca um registro (a data pode ter mudado).
  void updateEntry(String oldDate, FoodEntry e) {
    final newDate = dateKey(e.time);
    if (oldDate != newDate) {
      removeEntry(oldDate, e.id, keepPhoto: true);
      addEntry(e);
      return;
    }
    final d = day(oldDate);
    final i = d.entries.indexWhere((x) => x.id == e.id);
    if (i < 0) {
      d.entries.add(e);
    } else {
      d.entries[i] = e;
    }
    _saveDay(d);
  }

  void removeEntry(String date, String id, {bool keepPhoto = false}) {
    final d = day(date);
    final had = d.entries.any((x) => x.id == id && x.hasPhoto);
    d.entries.removeWhere((x) => x.id == id);
    _saveDay(d);
    if (had && !keepPhoto) removePhoto(id);
  }

  /// Guarda a foto (JPEG em base64) até ela ser enviada.
  void setPhoto(String entryId, String base64Jpeg) {
    _prefs.setString('$_kPhotoPrefix$entryId', base64Jpeg);
    clearDirty(dirtyPhotoDelete(entryId));
    _mark(dirtyPhoto(entryId));
    _changed();
  }

  void removePhoto(String entryId) {
    _prefs.remove('$_kPhotoPrefix$entryId');
    clearDirty(dirtyPhoto(entryId));
    _mark(dirtyPhotoDelete(entryId));
    _changed();
  }

  /// A foto subiu: a cópia do aparelho pode sair.
  void photoUploaded(String entryId) {
    _prefs.remove('$_kPhotoPrefix$entryId');
    clearDirty(dirtyPhoto(entryId));
  }

  void addWater(String date, int deltaMl) {
    final d = day(date);
    d.waterMl = (d.waterMl + deltaMl).clamp(0, 20000).toInt();
    _saveDay(d);
  }

  void setProfile(Profile p) {
    _profile = p;
    _prefs.setString(_kProfile, jsonEncode(p.toJson()));
    _mark(dirtyProfile);
    _changed();
  }

  void setGoals(Goals g) {
    _goals = g.stamped();
    _prefs.setString(_kGoals, jsonEncode(_goals.toJson()));
    _mark(dirtyGoals);
    _changed();
  }

  /// Conclui o cadastro inicial.
  void finishOnboarding(Profile p, Goals g) {
    _onboarded = true;
    _prefs.setBool(_kOnboarded, true);
    _profile = p;
    _prefs.setString(_kProfile, jsonEncode(p.toJson()));
    _mark(dirtyProfile);
    setGoals(g);
    if (p.weightKg > 0) addWeight(dateKey(DateTime.now()), p.weightKg);
  }

  void saveCustomFood(Food f) {
    _customFoods = [f, ..._customFoods.where((x) => x.id != f.id)];
    _prefs.setString(_kFoods, jsonEncode([for (final x in _customFoods) x.toJson()]));
    _mark(dirtyFoods);
    _changed();
  }

  void removeCustomFood(String id) {
    _customFoods = _customFoods.where((x) => x.id != id).toList();
    _prefs.setString(_kFoods, jsonEncode([for (final x in _customFoods) x.toJson()]));
    _mark(dirtyFoods);
    _changed();
  }

  /// Registra o peso do dia (um por dia) e atualiza o perfil.
  void addWeight(String date, double kg) {
    _weights = [..._weights.where((w) => w.date != date), WeightRecord(date, kg)]
      ..sort((a, b) => a.date.compareTo(b.date));
    _prefs.setString(_kWeights, jsonEncode([for (final w in _weights) w.toJson()]));
    _mark(dirtyWeights);
    if (_weights.last.date == date && _profile.weightKg != kg) {
      setProfile(_profile.copyWith(weightKg: kg));
    } else {
      _changed();
    }
  }

  void setAnamnesis(Anamnesis a) {
    _anamnesis = a;
    _prefs.setString(_kAnamnesis, jsonEncode(a.toJson()));
    _mark(dirtyAnamnesis);
    _changed();
  }

  void saveMeasure(BodyMeasure m) {
    _setMeasures(BodyMeasure.upsert(_measures, m));
    _mark(dirtyMeasures);
    _changed();
  }

  void removeMeasure(String date) {
    _setMeasures(_measures.where((m) => m.date != date).toList());
    _mark(dirtyMeasures);
    _changed();
  }

  void _setMeasures(List<BodyMeasure> list) {
    _measures = list;
    _prefs.setString(_kMeasures, jsonEncode([for (final m in list) m.toJson()]));
  }

  // ---- nuvem ----

  /// Versões online da anamnese e das medidas (o nutricionista também edita).
  void mergeRemoteAnamnesis(Anamnesis remote) {
    if (_dirty.contains(dirtyAnamnesis) || remote.updatedAt.isEmpty) return;
    if (remote.updatedAt.compareTo(_anamnesis.updatedAt) <= 0) return;
    _anamnesis = remote;
    _prefs.setString(_kAnamnesis, jsonEncode(remote.toJson()));
    notifyListeners();
  }

  void mergeRemoteMeasures(List<BodyMeasure> remote) {
    if (_dirty.contains(dirtyMeasures)) return;
    _setMeasures(remote);
    notifyListeners();
  }

  void setLinks(List<Link> links) {
    _links = links;
    _prefs.setString(_kLinks, jsonEncode([for (final l in links) l.toJson()]));
    notifyListeners();
  }

  /// Liga os dados do aparelho a uma conta. Se já eram de outra conta,
  /// o aparelho é limpo para não misturar pessoas.
  Future<void> bindOwner(String uid) async {
    if (_owner == uid) return;
    if (_owner != null) await wipe();
    _owner = uid;
    await _prefs.setString(_kOwner, uid);
    if (_onboarded) markAllDirty();
  }

  void markAllDirty() {
    _dirty.addAll([
      dirtyProfile, dirtyGoals, dirtyFoods, dirtyWeights, dirtyAnamnesis, dirtyMeasures,
      for (final d in _days.keys) dirtyDay(d),
    ]);
    _prefs.setStringList(_kDirty, _dirty.toList());
  }

  /// Apaga os dados deste aparelho (a nuvem não é tocada).
  Future<void> wipe() async {
    // a sessão da conta e os avisos em segundo plano ficam (são da Account e do Background)
    const keep = ['nv_fb_', 'nv_auto_signin', 'nv_background', 'nv_notified'];
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith('nv_') && !keep.any(key.startsWith)) await _prefs.remove(key);
    }
    _profile = const Profile();
    _goals = const Goals();
    _onboarded = false;
    _owner = null;
    _days.clear();
    _customFoods = [];
    _weights = [];
    _comments = {};
    _anamnesis = const Anamnesis();
    _measures = [];
    _links = [];
    _dirty = {};
    localMode = false;
    notifyListeners();
  }

  /// Metas vindas da nuvem valem se forem mais novas (ex.: o nutricionista ajustou).
  void mergeRemoteGoals(Object? remote) {
    if (remote is! Map) return;
    final g = Goals.fromJson(Map<String, dynamic>.from(remote));
    final mine = _goals.updatedAt;
    final theirs = g.updatedAt;
    if (theirs == null || (mine != null && !theirs.isAfter(mine))) return;
    _goals = g;
    _prefs.setString(_kGoals, jsonEncode(g.toJson()));
    clearDirty(dirtyGoals);
    notifyListeners();
  }

  void setComments(Map<String, DayComment> comments) {
    _comments = comments;
    _prefs.setString(_kComments, jsonEncode({for (final e in comments.entries) e.key: e.value.toJson()}));
    notifyListeners();
  }

  /// Tudo o que vai para a cópia no Drive.
  Map<String, dynamic> exportBackup() => {
        'app': 'NutriVitta',
        'format': 1,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'profile': _profile.toJson(),
        'goals': _goals.toJson(),
        'foods': [for (final f in _customFoods) f.toJson()],
        'weights': [for (final w in _weights) w.toJson()],
        'anamnesis': _anamnesis.toJson(),
        'measures': [for (final m in _measures) m.toJson()],
        'days': {for (final d in _days.values) d.date: d.toJson()},
      };

  /// Restaura os dados (do Drive ou do banco online) neste aparelho.
  Future<void> importBackup(Map<String, dynamic> b, {bool markDirty = false}) async {
    final profile = b['profile'];
    if (profile is! Map) return;
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith(_kDayPrefix)) await _prefs.remove(key);
    }
    _profile = Profile.fromJson(Map<String, dynamic>.from(profile));
    await _prefs.setString(_kProfile, jsonEncode(_profile.toJson()));
    final goals = b['goals'];
    _goals = goals is Map ? Goals.fromJson(Map<String, dynamic>.from(goals)) : _profile.suggestGoals();
    await _prefs.setString(_kGoals, jsonEncode(_goals.toJson()));
    _customFoods = [for (final f in (b['foods'] as List? ?? const [])) Food.fromJson(Map<String, dynamic>.from(f as Map))];
    await _prefs.setString(_kFoods, jsonEncode([for (final x in _customFoods) x.toJson()]));
    _weights = [for (final w in (b['weights'] as List? ?? const [])) WeightRecord.fromJson(Map<String, dynamic>.from(w as Map))];
    await _prefs.setString(_kWeights, jsonEncode([for (final w in _weights) w.toJson()]));
    final anam = b['anamnesis'];
    _anamnesis = Anamnesis.fromJson(anam is Map ? Map<String, dynamic>.from(anam) : null);
    await _prefs.setString(_kAnamnesis, jsonEncode(_anamnesis.toJson()));
    _setMeasures([for (final m in (b['measures'] as List? ?? const [])) BodyMeasure.fromJson(Map<String, dynamic>.from(m as Map))]);
    _days.clear();
    final days = b['days'];
    if (days is Map) {
      for (final e in days.entries) {
        final d = DayLog.fromJson('${e.key}', Map<String, dynamic>.from(e.value as Map));
        _days[d.date] = d;
        await _prefs.setString('$_kDayPrefix${d.date}', jsonEncode(d.toJson()));
      }
    }
    _onboarded = true;
    await _prefs.setBool(_kOnboarded, true);
    _dirty = {};
    if (markDirty) {
      markAllDirty();
    } else {
      await _prefs.setStringList(_kDirty, const []);
    }
    notifyListeners();
  }
}

/// Entrega o AppState para as telas.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}
