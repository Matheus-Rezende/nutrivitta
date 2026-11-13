import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary.dart';
import '../models/food.dart';
import '../util/format.dart';

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
  static const _kAutoSignIn = 'nv_auto_signin_v1';
  static const _kDayPrefix = 'nv_day_';

  // marcas de "falta enviar para a nuvem"
  static const dirtyProfile = 'profile';
  static const dirtyGoals = 'goals';
  static const dirtyFoods = 'foods';
  static const dirtyWeights = 'weights';
  static String dirtyDay(String date) => 'day:$date';

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
  Set<String> _dirty = {};

  /// A pessoa escolheu usar sem conta (só neste aparelho).
  bool localMode = false;

  /// Tentar o login silencioso ao abrir o app (desligado quando a pessoa sai da conta).
  bool get autoSignIn => _prefs.getBool(_kAutoSignIn) ?? false;

  Future<void> setAutoSignIn(bool value) => _prefs.setBool(_kAutoSignIn, value);

  void useLocalMode() {
    localMode = true;
    notifyListeners();
  }

  static Future<AppState> load() async {
    final results = await Future.wait([
      rootBundle.loadString('assets/foods.json'),
      SharedPreferences.getInstance(),
    ]);
    final state = AppState._(results[1] as SharedPreferences, FoodDb.parse(results[0] as String));
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
      removeEntry(oldDate, e.id);
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

  void removeEntry(String date, String id) {
    final d = day(date);
    d.entries.removeWhere((x) => x.id == id);
    _saveDay(d);
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

  // ---- nuvem ----

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
    _dirty.addAll([dirtyProfile, dirtyGoals, dirtyFoods, dirtyWeights, for (final d in _days.keys) dirtyDay(d)]);
    _prefs.setStringList(_kDirty, _dirty.toList());
  }

  /// Apaga os dados deste aparelho (a nuvem não é tocada).
  Future<void> wipe() async {
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith('nv_')) await _prefs.remove(key);
    }
    _profile = const Profile();
    _goals = const Goals();
    _onboarded = false;
    _owner = null;
    _days.clear();
    _customFoods = [];
    _weights = [];
    _comments = {};
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
