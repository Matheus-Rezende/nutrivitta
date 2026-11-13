import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import 'background.dart';
import 'state/app_state.dart';

/// Sincronização do app do paciente: envia o que mudou no aparelho, busca
/// metas, recados, anamnese, medidas e pedidos de conexão, e mantém a cópia
/// no Google Drive.
class Sync extends ChangeNotifier with WidgetsBindingObserver {
  Sync._();

  static final instance = Sync._();

  late AppState _state;
  final _account = Account.instance;
  final _remote = Remote.instance;

  bool busy = false;
  String? message;
  DateTime? lastSync;
  DateTime? lastDriveBackup;

  /// Procurando dados já salvos logo depois do login (o cadastro espera).
  bool restoring = false;

  bool _pulled = false;
  bool _again = false;
  bool _driveDirty = false;
  Timer? _debounce;

  Future<void> init(AppState state) async {
    _state = state;
    state.onSaved = _changed;
    _account.onSignedIn = _onSignedIn;
    _account.onSignedOut = () {
      _pulled = false;
      _debounce?.cancel();
    };
    WidgetsBinding.instance.addObserver(this);
    await _account.init(scopes: const [DriveBackup.scope]);
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
      notifyListeners();
    }
    unawaited(Background.instance.enable());
  }

  /// Sai da conta neste aparelho; os dados continuam aqui e na nuvem.
  Future<void> signOut() async {
    await Background.instance.disable();
    await _account.signOut();
  }

  void _changed() {
    _driveDirty = true;
    if (!_account.signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(run()));
  }

  /// Busca de novo metas, recados e pedidos (puxar para atualizar, voltar ao app).
  Future<void> refresh({bool userAsked = true}) {
    _pulled = false;
    return run(userAsked: userAsked);
  }

  Future<void> run({bool userAsked = false}) async {
    if (!_account.signedIn) return;
    if (busy) {
      _again = true;
      return;
    }
    busy = true;
    message = null;
    notifyListeners();
    try {
      if (_account.online) await _firestore();
      await _drive(userAsked: userAsked);
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
        await Background.instance.markSeen(_state);
      }
      _pulled = true;
    }
    if (!_state.onboarded) return;
    // envia o que mudou; cada item só sai da fila depois de gravado
    for (final item in _state.dirty.toList()) {
      if (item == AppState.dirtyProfile) {
        var p = _state.profile;
        if (p.email.isEmpty || p.name.isEmpty) {
          p = p.copyWith(email: p.email.isEmpty ? _account.email : p.email, name: p.name.isEmpty ? _account.name : p.name);
        }
        await _remote.saveProfile(uid, p);
        if (_account.email.isNotEmpty) await _remote.publishDirectory(uid, _account.email, p.name);
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

  String _photoDate(String entryId) {
    for (final d in _state.days.values) {
      if (d.entries.any((e) => e.id == entryId)) return d.date;
    }
    return dateKey(DateTime.now());
  }

  /// Guarda os pedidos e mantém a lista de autorizados coerente com eles:
  /// se o nutricionista encerrou o vínculo, ele sai da lista.
  Future<void> _applyLinks(String uid, List<Link> links) async {
    links.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _state.setLinks(links);
    final allowed = _state.profile.nutritionistUids;
    final keep = [
      for (final p in allowed)
        if (links.any((l) => l.proUid == p && l.accepted)) p,
    ];
    if (keep.length != allowed.length) {
      final p = _state.profile.copyWith(nutritionistUids: keep);
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
    _driveDirty = true;
    message = 'Seus dados foram restaurados.';
  }

  Future<void> _drive({required bool userAsked}) async {
    final drive = await _account.drive();
    if (drive == null) return;
    if (!_state.onboarded) {
      // conta sem dados no banco online: tenta a cópia do Drive
      final backup = await drive.download();
      if (backup != null) {
        await _state.importBackup(backup, markDirty: true);
        message = 'Seus dados foram restaurados do Google Drive.';
        _again = _account.online;
      }
      return;
    }
    if (!_driveDirty && lastDriveBackup != null && !userAsked) return;
    await drive.upload(_state.exportBackup());
    _driveDirty = false;
    lastDriveBackup = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _account.signedIn && !busy) {
      final last = lastSync;
      if (last == null || DateTime.now().difference(last).inMinutes >= 2) unawaited(refresh(userAsked: false));
    } else if (state == AppLifecycleState.paused && _account.signedIn && _state.dirty.isNotEmpty) {
      _debounce?.cancel();
      unawaited(run());
    }
  }

  void clearMessage() {
    if (message == null) return;
    message = null;
    notifyListeners();
  }
}
