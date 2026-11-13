import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/diary.dart';
import '../state/app_state.dart';
import 'account.dart';
import 'firebase_rest.dart';
import 'remote.dart';

/// Sincronização: envia para o banco online o que mudou no aparelho, busca
/// as metas e os recados do nutricionista e mantém a cópia no Google Drive.
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
    // só tenta o login silencioso se a pessoa entrou e não saiu da conta
    await _account.init(silent: state.autoSignIn);
  }

  Future<void> _onSignedIn() async {
    final uid = _account.uid;
    if (uid == null) return;
    await _state.bindOwner(uid);
    await _state.setAutoSignIn(true);
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
  }

  /// Sai da conta neste aparelho; os dados continuam aqui e na nuvem.
  Future<void> signOut() async {
    await _state.setAutoSignIn(false);
    await _account.signOut();
  }

  void _changed() {
    _driveDirty = true;
    if (!_account.signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(run()));
  }

  /// Busca de novo as metas e os recados (puxar para atualizar, voltar ao app).
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
      if (remote != null && remote['role'] != null) {
        if (!_state.onboarded) {
          await _restoreFromFirestore(uid, remote);
        } else {
          _state.mergeRemoteGoals(remote['goals']);
        }
      } else if (_state.onboarded) {
        _state.markAllDirty();
      }
      if (_state.onboarded && !_state.profile.isNutritionist) {
        _state.setComments(await _remote.comments(uid));
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
        if (p.isNutritionist) await _remote.updateInvite(uid, p);
      } else if (item == AppState.dirtyGoals) {
        await _remote.saveGoals(uid, _state.goals);
      } else if (item == AppState.dirtyFoods) {
        await _remote.saveMeta(uid, 'foods', [for (final f in _state.customFoods) f.toJson()]);
      } else if (item == AppState.dirtyWeights) {
        await _remote.saveMeta(uid, 'weights', [for (final w in _state.weights) w.toJson()]);
      } else if (item.startsWith('day:')) {
        await _remote.saveDay(uid, _state.day(item.substring(4)));
      }
      _state.clearDirty(item);
    }
  }

  Future<void> _restoreFromFirestore(String uid, Map<String, dynamic> user) async {
    final results = await Future.wait<Object>([
      _remote.allDays(uid),
      _remote.meta(uid, 'foods'),
      _remote.meta(uid, 'weights'),
    ]);
    final days = results[0] as List<DayLog>;
    await _state.importBackup({
      'profile': user,
      'goals': user['goals'],
      'foods': results[1],
      'weights': results[2],
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
      if (last == null || DateTime.now().difference(last).inMinutes >= 5) unawaited(refresh(userAsked: false));
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
