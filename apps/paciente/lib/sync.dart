import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import 'background.dart';
import 'state/app_state.dart';

/// Sincronização do app do paciente: envia o que mudou no aparelho, busca
/// metas, recados, anamnese, medidas e pedidos de conexão.
class Sync extends ChangeNotifier with WidgetsBindingObserver {
  Sync._();

  static final instance = Sync._();

  late AppState _state;
  final _account = Account.instance;
  final _remote = Remote.instance;

  bool busy = false;
  String? message;
  DateTime? lastSync;

  /// Procurando dados já salvos logo depois do login (o cadastro espera).
  bool restoring = false;

  /// A busca dos dados salvos falhou: o cadastro em branco não aparece, para
  /// não sobrescrever o perfil que está online.
  bool restoreFailed = false;

  bool _pulled = false;
  bool _again = false;
  Timer? _debounce;

  /// Verificação rápida com o app aberto (pedidos e recados novos).
  Timer? _poll;
  bool _polling = false;
  static const pollEvery = Duration(seconds: 15);

  Future<void> init(AppState state) async {
    _state = state;
    state.onSaved = _changed;
    _account.onSignedIn = _onSignedIn;
    _account.onSignedOut = () {
      _pulled = false;
      _debounce?.cancel();
      _stopPolling();
    };
    WidgetsBinding.instance.addObserver(this);
    await _account.init();
  }

  Future<void> _onSignedIn() async {
    final uid = _account.uid;
    if (uid == null) return;
    await _state.bindOwner(uid);
    _pulled = false;
    if (!_state.onboarded) {
      restoring = true;
      notifyListeners();
    }
    await run();
    while (busy || _again) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (restoring) {
      restoring = false;
      restoreFailed = _account.online && !_state.onboarded && !_pulled;
      notifyListeners();
    }
    unawaited(Background.instance.enable());
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) => unawaited(_quickCheck()));
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Busca só pedidos e recados recentes (leve), sem mexer na fila de envio.
  Future<void> _quickCheck() async {
    final uid = _account.uid;
    if (_polling || busy || !_account.online || uid == null || !_state.onboarded) return;
    _polling = true;
    var pullAgain = false;
    try {
      final results = await Future.wait<Object>([
        _remote.linksOfPatient(uid),
        _remote.recentComments(uid, Background.recentSince),
      ]);
      final links = results[0] as List<Link>;
      final recent = results[1] as Map<String, DayComment>;
      final before = {for (final l in _state.links) l.id: '${l.status.name}|${l.updatedAt}|${l.anamnesisRequest}'};
      final after = {for (final l in links) l.id: '${l.status.name}|${l.updatedAt}|${l.anamnesisRequest}'};
      // o nutricionista mudou metas, medidas, anamnese ou recados
      final changedBefore = {for (final l in _state.links) l.id: l.changeAt};
      final dataChanged = links.any((l) => l.accepted && l.changeAt.isNotEmpty && changedBefore[l.id] != l.changeAt);
      if (!mapEquals(before, after) || dataChanged) await _applyLinks(uid, links);
      final changed = recent.entries.any((e) => _state.comment(e.key)?.updatedAt != e.value.updatedAt);
      if (changed) _state.setComments({..._state.comments, ...recent});
      await Background.report(links, recent);
      if (dataChanged) pullAgain = true;
    } catch (e) {
      debugPrint('Verificação rápida: $e');
    }
    _polling = false;
    if (pullAgain) unawaited(refresh(userAsked: false));
  }

  /// Tenta de novo buscar os dados salvos (tela de erro do cadastro).
  Future<void> retryRestore() async {
    restoreFailed = false;
    restoring = true;
    notifyListeners();
    _pulled = false;
    await run(userAsked: true);
    while (busy || _again) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    restoring = false;
    restoreFailed = _account.online && !_state.onboarded && !_pulled;
    notifyListeners();
  }

  /// Começa do zero mesmo sem conseguir buscar os dados salvos.
  void skipRestore() {
    restoreFailed = false;
    notifyListeners();
  }

  /// Sai da conta neste aparelho; os dados continuam na nuvem.
  Future<void> signOut() async {
    await Background.instance.disable();
    await _account.signOut();
  }

  /// Envia o que falta e devolve quantas alterações ainda não subiram.
  Future<int> flush() async {
    if (_account.online && _state.dirty.isNotEmpty) {
      _debounce?.cancel();
      await run();
      while (busy || _again) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    return _account.signedIn ? _state.dirty.length : 0;
  }

  /// Sai da conta e limpa este aparelho: o app volta para a tela de entrar.
  /// Tudo o que já foi enviado volta quando a pessoa entrar de novo.
  Future<void> signOutAndClear() async {
    await signOut();
    await _state.wipe();
  }

  /// O paciente apaga o recado do nutricionista de um dia.
  Future<void> deleteComment(String date) async {
    final uid = _account.uid;
    if (!_account.online || uid == null) throw StateError('offline');
    await _remote.deleteComment(uid, date);
    _state.setComments({..._state.comments}..remove(date));
  }

  void _changed() {
    if (!_account.online) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(run()));
  }

  /// Busca de novo metas, recados e pedidos (puxar para atualizar, voltar ao app).
  Future<void> refresh({bool userAsked = true}) {
    _pulled = false;
    return run(userAsked: userAsked);
  }

  Future<void> run({bool userAsked = false}) async {
    if (!_account.online) return;
    if (busy) {
      _again = true;
      return;
    }
    busy = true;
    message = null;
    notifyListeners();
    try {
      await _firestore();
      lastSync = DateTime.now();
    } on CloudException catch (e) {
      debugPrint('Sincronização: $e');
      message = e.denied
          ? 'A nuvem recusou o acesso. Confira as regras do Firestore (CONFIGURACAO.md).'
          : 'Não foi possível sincronizar agora. Seus dados estão salvos no aparelho.';
    } catch (e) {
      debugPrint('Sincronização: $e');
      message = userAsked ? 'Sem conexão agora. Seus dados estão salvos no aparelho.' : null;
    }
    busy = false;
    notifyListeners();
    if (_again) {
      _again = false;
      unawaited(run());
    }
  }

  Future<void> _firestore() async {
    final uid = _account.uid!;
    if (!_pulled) {
      final remote = await _remote.user(uid);
      if (remote != null && remote['name'] != null) {
        if (!_state.onboarded) {
          await _restoreFromFirestore(uid, remote);
        } else {
          _state.mergeRemoteGoals(remote['goals']);
        }
      } else if (_state.onboarded) {
        _state.markAllDirty();
      }
      if (_state.onboarded) {
        final results = await Future.wait<Object>([
          _remote.comments(uid),
          _remote.anamnesis(uid),
          _remote.measures(uid),
          _remote.linksOfPatient(uid),
        ]);
        _state.setComments(results[0] as Map<String, DayComment>);
        _state.mergeRemoteAnamnesis(results[1] as Anamnesis);
        _state.mergeRemoteMeasures(results[2] as List<BodyMeasure>);
        await _applyLinks(uid, results[3] as List<Link>);
        await Background.report(results[3] as List<Link>, results[0] as Map<String, DayComment>);
      }
      _pulled = true;
    }
    if (!_state.onboarded) return;
    await _ensureCode(uid);
    // envia o que mudou; cada item só sai da fila depois de gravado
    for (final item in _state.dirty.toList()) {
      if (item == AppState.dirtyProfile) {
        var p = _state.profile;
        if (p.email.isEmpty || p.name.isEmpty) {
          p = p.copyWith(email: p.email.isEmpty ? _account.email : p.email, name: p.name.isEmpty ? _account.name : p.name);
        }
        await _remote.saveProfile(uid, p);
        if (p.code.isNotEmpty) await _remote.renameCode(uid, p.code, p.name);
      } else if (item == AppState.dirtyGoals) {
        await _remote.saveGoals(uid, _state.goals);
      } else if (item == AppState.dirtyFoods) {
        await _remote.saveMeta(uid, 'foods', [for (final f in _state.customFoods) f.toJson()]);
      } else if (item == AppState.dirtyWeights) {
        await _remote.saveMeta(uid, 'weights', [for (final w in _state.weights) w.toJson()]);
      } else if (item == AppState.dirtyAnamnesis) {
        final a = _state.anamnesis;
        await _remote.saveAnamnesis(
            uid, Anamnesis(a.answers, DateTime.now().toUtc().toIso8601String(), _state.profile.name));
      } else if (item == AppState.dirtyMeasures) {
        await _remote.saveMeasures(uid, _state.measures);
      } else if (item.startsWith('day:')) {
        await _remote.saveDay(uid, _state.day(item.substring(4)));
      } else if (item.startsWith('photo:')) {
        final id = item.substring(6);
        final data = _state.localPhoto(id);
        if (data != null) {
          await _remote.savePhoto(uid, id, _photoDate(id), data);
          _state.photoUploaded(id);
        }
      } else if (item.startsWith('photodel:')) {
        await _remote.deletePhoto(uid, item.substring(9));
      }
      _state.clearDirty(item);
    }
  }

  /// Garante que o paciente tem um código e apaga o registro antigo por e-mail.
  Future<void> _ensureCode(String uid) async {
    if (_state.profile.code.isEmpty) {
      final code = await _remote.claimCode(uid, _state.profile.name);
      _state.setProfile(_state.profile.copyWith(code: code));
    }
    if (!_state.directoryCleaned && _account.email.isNotEmpty) {
      try {
        await _remote.deleteDirectory(_account.email);
      } catch (_) {
        // não existia (ou já foi apagado)
      }
      _state.markDirectoryCleaned();
    }
  }

  /// Troca o código do paciente (o antigo deixa de funcionar).
  Future<String> newCode() async {
    final uid = _account.uid;
    if (!_account.online || uid == null) throw StateError('offline');
    final old = _state.profile.code;
    final code = await _remote.claimCode(uid, _state.profile.name);
    final p = _state.profile.copyWith(code: code);
    await _remote.saveProfile(uid, p);
    _state.setProfile(p);
    _state.clearDirty(AppState.dirtyProfile);
    if (old.isNotEmpty) {
      try {
        await _remote.releaseCode(old);
      } catch (_) {}
    }
    return code;
  }

  /// A foto se chama aaaa-mm-dd_refeição.
  String _photoDate(String photoId) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(photoId)?.group(0) ?? dateKey(DateTime.now());

  /// Guarda os pedidos e mantém a lista de autorizados igual aos vínculos
  /// aceitos (só o paciente aceita um vínculo). Assim, se o perfil voltar sem
  /// a lista (ex.: dados apagados no aparelho), o acesso do nutricionista é
  /// refeito; se o nutricionista encerrou, ele sai da lista.
  Future<void> _applyLinks(String uid, List<Link> links) async {
    links.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _state.setLinks(links);
    final allowed = {..._state.profile.nutritionistUids};
    final accepted = {for (final l in links) if (l.accepted) l.proUid};
    if (allowed.length != accepted.length || !allowed.containsAll(accepted)) {
      final p = _state.profile.copyWith(nutritionistUids: accepted.toList());
      await _remote.saveProfile(uid, p);
      _state.setProfile(p);
      _state.clearDirty(AppState.dirtyProfile);
    }
  }

  /// O paciente aceita, recusa ou encerra um vínculo.
  Future<void> answer(Link link, LinkStatus status) async {
    final uid = _account.uid;
    if (!_account.online || uid == null) throw StateError('offline');
    final ids = {..._state.profile.nutritionistUids};
    if (status == LinkStatus.accepted) {
      ids.add(link.proUid);
    } else {
      ids.remove(link.proUid);
    }
    final profile = _state.profile.copyWith(nutritionistUids: ids.toList());
    if (status == LinkStatus.accepted) {
      // primeiro o vínculo, depois a autorização
      await _remote.answerLink(link, status);
      await _remote.saveProfile(uid, profile);
    } else {
      // primeiro tira a autorização, depois responde
      await _remote.saveProfile(uid, profile);
      await _remote.answerLink(link, status);
    }
    _state.setProfile(profile);
    _state.clearDirty(AppState.dirtyProfile);
    _state.setLinks([
      for (final l in _state.links) l.id == link.id ? l.withStatus(status) : l,
    ]);
  }

  /// O paciente responde ao pedido de edição da anamnese ([grant]) ou revoga
  /// uma permissão já dada ([grant] = false).
  Future<void> answerAnamnesis(Link link, {required bool grant}) async {
    if (!_account.online) throw StateError('offline');
    final now = DateTime.now();
    final updated = link.copyWith(
      anamnesisRequest: grant ? 'granted' : 'denied',
      anamnesisAnsweredAt: now.toUtc().toIso8601String(),
      anamnesisUntil: grant ? now.add(Link.anamnesisGrant).millisecondsSinceEpoch : 0,
    );
    await _remote.updateLink(updated, {
      'anamnesisRequest': updated.anamnesisRequest,
      'anamnesisAnsweredAt': updated.anamnesisAnsweredAt,
      'anamnesisUntil': updated.anamnesisUntil,
      'updatedAt': updated.updatedAt,
    });
    _state.setLinks([for (final l in _state.links) l.id == link.id ? updated : l]);
  }

  Future<void> _restoreFromFirestore(String uid, Map<String, dynamic> user) async {
    final results = await Future.wait<Object>([
      _remote.allDays(uid),
      _remote.meta(uid, 'foods'),
      _remote.meta(uid, 'weights'),
      _remote.anamnesis(uid),
      _remote.measures(uid),
    ]);
    final days = results[0] as List<DayLog>;
    await _state.importBackup({
      'profile': user,
      'goals': user['goals'],
      'foods': results[1],
      'weights': results[2],
      'anamnesis': (results[3] as Anamnesis).toJson(),
      'measures': [for (final m in results[4] as List<BodyMeasure>) m.toJson()],
      'days': {for (final d in days) d.date: d.toJson()},
    });
    message = 'Seus dados foram restaurados.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _account.online) {
      _startPolling();
      final last = lastSync;
      if (!busy && (last == null || DateTime.now().difference(last).inMinutes >= 2)) {
        unawaited(refresh(userAsked: false));
      } else {
        unawaited(_quickCheck());
      }
    } else if (state == AppLifecycleState.paused) {
      // em segundo plano, quem verifica é o WorkManager
      _stopPolling();
      if (_account.online && _state.dirty.isNotEmpty) {
        _debounce?.cancel();
        unawaited(run());
      }
    }
  }

  void clearMessage() {
    if (message == null) return;
    message = null;
    notifyListeners();
  }
}
