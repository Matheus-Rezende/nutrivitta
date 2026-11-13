import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resultado do envio de um pedido de conexão.
enum InviteResult { sent, notFound, alreadyConnected, alreadyPending, self }

/// Estado do app do nutricionista: perfil profissional e pedidos/pacientes.
/// Tudo fica online; o aparelho guarda só uma cópia do perfil para abrir rápido.
class ProState extends ChangeNotifier {
  ProState._(this._prefs);

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
  }

  void onSignedOut() {
    links = [];
    notifyListeners();
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

  /// Envia o pedido de conexão para o paciente com este e-mail.
  Future<InviteResult> invite(String email, String message) async {
    final uid = _account.uid;
    final me = profile;
    if (uid == null || me == null || !_account.online) throw StateError('offline');
    if (Remote.emailKey(email) == _account.email) return InviteResult.self;
    final found = await _remote.findPatient(email);
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
      patientEmail: Remote.emailKey(email),
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
    await _remote.saveLink(link.withStatus(status));
    links = [for (final l in links) l.id == link.id ? l.withStatus(status) : l];
    notifyListeners();
  }

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
