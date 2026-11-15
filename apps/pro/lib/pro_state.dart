import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background.dart';

/// Resultado do envio de um pedido de conexão.
enum InviteResult { sent, notFound, alreadyConnected, alreadyPending, self }

/// Estado do app do nutricionista: perfil profissional e pedidos/pacientes.
/// Tudo fica online; o aparelho guarda só uma cópia do perfil para abrir rápido.
class ProState extends ChangeNotifier with WidgetsBindingObserver {
  ProState._(this._prefs) {
    WidgetsBinding.instance.addObserver(this);
  }

  static const _kProfile = 'nv_pro_profile_v1';
  static const _kOwner = 'nv_pro_owner_v1';

  final SharedPreferences _prefs;
  final _account = Account.instance;
  final _remote = Remote.instance;

  ProProfile? profile;
  List<Link> links = [];

  /// Carregando o perfil logo depois do login.
  bool loadingProfile = false;
  bool loadingLinks = false;
  String? error;

  /// Verificação rápida com o app aberto (respostas dos pacientes).
  Timer? _poll;
  bool _polling = false;
  static const pollEvery = Duration(seconds: 15);

  static Future<ProState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = ProState._(prefs);
    final raw = prefs.getString(_kProfile);
    if (raw != null) {
      try {
        s.profile = ProProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    return s;
  }

  bool get ready => profile != null && profile!.isComplete;

  List<Link> get patients => links.where((l) => l.accepted).toList()
    ..sort((a, b) => a.patientLabel.toLowerCase().compareTo(b.patientLabel.toLowerCase()));

  List<Link> get waiting => links.where((l) => l.pending).toList();

  List<Link> get declined => links.where((l) => l.status == LinkStatus.declined).toList();

  /// Depois do login: busca o perfil profissional e os pacientes.
  Future<void> onSignedIn() async {
    final uid = _account.uid;
    if (uid == null) return;
    if (_prefs.getString(_kOwner) != uid) {
      profile = null;
      links = [];
      await _prefs.remove(_kProfile);
      await _prefs.setString(_kOwner, uid);
    }
    if (!_account.online) {
      notifyListeners();
      return;
    }
    loadingProfile = profile == null;
    notifyListeners();
    try {
      final p = await _remote.pro(uid);
      if (p != null) _setProfile(p);
      error = null;
    } catch (e) {
      error = 'Não foi possível carregar seu perfil. Confira a internet.';
    }
    loadingProfile = false;
    notifyListeners();
    if (ready) await refresh();
    unawaited(ProAlerts.enable());
    _startPolling();
  }

  void onSignedOut() {
    links = [];
    _stopPolling();
    unawaited(Alerts.disable());
    notifyListeners();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) => unawaited(_quickCheck()));
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Atualiza a lista sem mostrar carregamento e avisa as respostas novas.
  Future<void> _quickCheck() async {
    final uid = _account.uid;
    if (_polling || loadingLinks || !_account.online || uid == null || !ready) return;
    _polling = true;
    try {
      final fresh = await _remote.linksOfPro(uid);
      fresh.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final before = {for (final l in links) l.id: '${l.status.name}|${l.updatedAt}|${l.anamnesisRequest}|${l.anamnesisUntil}'};
      final after = {for (final l in fresh) l.id: '${l.status.name}|${l.updatedAt}|${l.anamnesisRequest}|${l.anamnesisUntil}'};
      if (!mapEquals(before, after)) {
        links = fresh;
        error = null;
        notifyListeners();
      }
      await ProAlerts.report(fresh);
    } catch (e) {
      debugPrint('Verificação rápida: $e');
    }
    _polling = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_account.signedIn) return;
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      unawaited(_quickCheck());
    } else if (state == AppLifecycleState.paused) {
      // em segundo plano, quem verifica é o WorkManager
      _stopPolling();
    }
  }

  void _setProfile(ProProfile p) {
    profile = p;
    _prefs.setString(_kProfile, jsonEncode(p.toJson()));
  }

  Future<void> saveProfile(ProProfile p) async {
    final uid = _account.uid;
    if (uid == null || !_account.online) throw StateError('offline');
    final full = p.copyWith(email: _account.email);
    await _remote.savePro(uid, full);
    _setProfile(full);
    notifyListeners();
  }

  /// Atualiza a lista de pedidos e pacientes.
  Future<void> refresh() async {
    final uid = _account.uid;
    if (uid == null || !_account.online || loadingLinks) return;
    loadingLinks = true;
    notifyListeners();
    try {
      links = await _remote.linksOfPro(uid);
      links.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      error = null;
      unawaited(ProAlerts.report(links));
    } on CloudException catch (e) {
      error = e.denied
          ? 'A nuvem recusou o acesso. Confira as regras do Firestore (CONFIGURACAO.md).'
          : 'Não foi possível atualizar a lista agora.';
    } catch (e) {
      error = 'Sem conexão agora.';
    }
    loadingLinks = false;
    notifyListeners();
  }

  /// Envia o pedido de conexão para o paciente dono deste código.
  Future<InviteResult> invite(String code, String message) async {
    final uid = _account.uid;
    final me = profile;
    if (uid == null || me == null || !_account.online) throw StateError('offline');
    final found = await _remote.findPatientByCode(code);
    if (found == null) return InviteResult.notFound;
    final (patientUid, patientName) = found;
    if (patientUid == uid) return InviteResult.self;
    final existing = links.where((l) => l.patientUid == patientUid).firstOrNull;
    if (existing != null && existing.accepted) return InviteResult.alreadyConnected;
    if (existing != null && existing.pending) return InviteResult.alreadyPending;
    final link = Link(
      proUid: uid,
      patientUid: patientUid,
      proName: me.name,
      proCrn: me.crn,
      patientName: patientName,
      message: message.trim(),
      createdAt: existing?.createdAt ?? '',
    );
    await _remote.saveLink(link);
    links = [link, ...links.where((l) => l.id != link.id)];
    notifyListeners();
    return InviteResult.sent;
  }

  /// Cancela um pedido ainda sem resposta, ou encerra o acompanhamento.
  Future<void> close(Link link) async {
    final status = link.accepted ? LinkStatus.ended : LinkStatus.cancelled;
    final closed = link.withStatus(status);
    // a própria ação não vira notificação
    await Alerts.deliver(const [], quietKeys: {'link:${closed.id}:${closed.status.name}:${closed.updatedAt}'});
    // só o status muda (o resto do vínculo fica como está no banco)
    await _remote.updateLink(closed, {'status': closed.status.name, 'updatedAt': closed.updatedAt});
    links = [for (final l in links) l.id == link.id ? closed : l];
    notifyListeners();
  }

  /// Pede ao paciente permissão para editar a anamnese.
  Future<void> requestAnamnesis(Link link) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final asked = link.copyWith(anamnesisRequest: 'pending', anamnesisRequestedAt: now);
    await _remote.updateLink(asked, {
      'anamnesisRequest': 'pending',
      'anamnesisRequestedAt': now,
      'updatedAt': asked.updatedAt,
    });
    links = [for (final l in links) l.id == link.id ? asked : l];
    notifyListeners();
  }

  /// Vínculo atualizado (a lista é renovada a cada 15 segundos).
  Link current(Link link) => links.where((l) => l.id == link.id).firstOrNull ?? link;

  /// Tira da lista um pedido recusado, cancelado ou encerrado.
  Future<void> forget(Link link) async {
    await _remote.deleteLink(link);
    links = links.where((l) => l.id != link.id).toList();
    notifyListeners();
  }
}

/// Entrega o ProState para as telas.
class ProScope extends InheritedNotifier<ProState> {
  const ProScope({super.key, required ProState state, required super.child}) : super(notifier: state);

  static ProState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ProScope>()!.notifier!;

  static ProState read(BuildContext context) => context.getInheritedWidgetOfExactType<ProScope>()!.notifier!;
}
