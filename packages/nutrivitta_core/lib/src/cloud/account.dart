import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'firebase_rest.dart';

/// Conta do NutriVitta: cadastro e login com e-mail e senha no Firebase
/// Authentication. O app só libera os dados depois que o e-mail é confirmado.
class Account extends ChangeNotifier {
  Account._();

  static final instance = Account._();

  static const _kRefresh = 'nv_fb_refresh_v1';
  static const _kUid = 'nv_fb_uid_v1';
  static const _kEmail = 'nv_fb_email_v1';
  static const _kName = 'nv_fb_name_v1';
  static const _kVerified = 'nv_fb_verified_v1';

  /// Tamanho mínimo da senha.
  static const minPassword = 8;

  final _auth = FirebaseAuthRest(kFirebaseApiKey);

  FirebaseSession? _session;
  SharedPreferences? _prefs;
  String? _uid;
  String _email = '';
  String _name = '';
  bool _verified = false;
  Future<FirebaseSession?>? _restoring;

  bool busy = false;
  String? error;

  /// Chamado quando a conta entra já confirmada (login ou ao abrir o app).
  Future<void> Function()? onSignedIn;

  /// Chamado quando a conta sai.
  VoidCallback? onSignedOut;

  bool get firebaseConfigured => kFirebaseApiKey.isNotEmpty && kFirebaseProjectId.isNotEmpty;

  /// Cadastro e login disponíveis (o servidor está configurado).
  bool get supported => firebaseConfigured;

  /// Há uma conta neste aparelho (confirmada ou não).
  bool get signedIn => _uid != null;

  /// E-mail já confirmado pelo link.
  bool get verified => _verified;

  /// Pode usar o banco online: conta com e-mail confirmado.
  bool get online => signedIn && _verified;

  String? get uid => _uid;
  String get name => _name;
  String get email => _email;

  /// Abre a conta guardada neste aparelho, se houver.
  Future<void> init() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    final refresh = p.getString(_kRefresh);
    if (refresh == null || refresh.isEmpty) return;
    _uid = p.getString(_kUid);
    _email = p.getString(_kEmail) ?? '';
    _name = p.getString(_kName) ?? '';
    _verified = p.getBool(_kVerified) ?? false;
    if (_uid == null) return;
    notifyListeners();
    if (_verified) {
      unawaited(Future(() async => onSignedIn?.call()));
    } else {
      unawaited(checkVerified());
    }
  }

  Future<void> _remember(FirebaseSession s) async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setString(_kRefresh, s.refreshToken);
    await p.setString(_kUid, s.uid);
  }

  Future<void> _rememberUser() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setString(_kEmail, _email);
    await p.setString(_kName, _name);
    await p.setBool(_kVerified, _verified);
  }

  Future<String?> _run(Future<void> Function() action) async {
    if (busy) return null;
    busy = true;
    error = null;
    notifyListeners();
    String? message;
    try {
      await action();
    } catch (e) {
      debugPrint('Conta: $e');
      message = authMessage(e);
    }
    busy = false;
    notifyListeners();
    return message;
  }

  static String _clean(String email) => email.trim().toLowerCase();

  /// Cria a conta e envia o e-mail de confirmação. Devolve a mensagem de erro, ou null.
  Future<String?> register({required String name, required String email, required String password}) {
    return _run(() async {
      final s = await _auth.signUp(_clean(email), password);
      _session = s;
      await _remember(s);
      _uid = s.uid;
      _email = _clean(email);
      _name = name.trim();
      _verified = false;
      await _rememberUser();
      try {
        await _auth.setDisplayName(s.idToken, _name);
      } catch (e) {
        debugPrint('Nome da conta: $e');
      }
      try {
        await _auth.sendVerification(s.idToken);
      } catch (e) {
        debugPrint('E-mail de confirmação: $e');
      }
    });
  }

  /// Entra com e-mail e senha. Devolve a mensagem de erro, ou null.
  Future<String?> signIn({required String email, required String password}) async {
    final message = await _run(() async {
      final s = await _auth.signInWithPassword(_clean(email), password);
      _session = s;
      await _remember(s);
      final u = await _auth.lookup(s.idToken);
      _uid = s.uid;
      _email = u.email.isEmpty ? _clean(email) : u.email;
      _name = u.name;
      _verified = u.verified;
      await _rememberUser();
    });
    if (message == null && _verified) await onSignedIn?.call();
    return message;
  }

  /// Envia de novo o link de confirmação. Devolve a mensagem de erro, ou null.
  Future<String?> resendVerification() {
    return _run(() async {
      final t = await token();
      if (t == null) throw StateError('sem sessão');
      await _auth.sendVerification(t);
    });
  }

  /// Envia o link para criar uma senha nova. Devolve a mensagem de erro, ou null.
  Future<String?> resetPassword(String email) => _run(() => _auth.sendPasswordReset(_clean(email)));

  /// Confere no servidor se o e-mail já foi confirmado. Quando foi, renova a
  /// sessão (o banco só aceita a sessão emitida depois da confirmação) e libera o app.
  Future<bool> checkVerified() async {
    if (!signedIn) return false;
    if (_verified) return true;
    try {
      final t = await token();
      if (t == null) return false;
      final u = await _auth.lookup(t);
      if (u.name.isNotEmpty) _name = u.name;
      if (!u.verified) return false;
      _session = await _auth.restore(_session!.refreshToken);
      await _remember(_session!);
      _verified = true;
      await _rememberUser();
      notifyListeners();
      await onSignedIn?.call();
      return true;
    } catch (e) {
      debugPrint('Confirmação do e-mail: $e');
      return false;
    }
  }

  /// Sai da conta neste aparelho. Os dados continuam na nuvem.
  Future<void> signOut() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    for (final k in [_kRefresh, _kUid, _kEmail, _kName, _kVerified]) {
      await p.remove(k);
    }
    final had = _uid != null;
    _session = null;
    _uid = null;
    _email = '';
    _name = '';
    _verified = false;
    error = null;
    if (had) onSignedOut?.call();
    notifyListeners();
  }

  /// Token da sessão do Firebase, renovado quando está para vencer.
  Future<String?> token() async {
    final s = _session;
    if (s != null && s.valid) return s.idToken;
    final fresh = await (_restoring ??= _restore().whenComplete(() => _restoring = null));
    return fresh?.idToken;
  }

  Future<FirebaseSession?> _restore() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    final refresh = _session?.refreshToken ?? p.getString(_kRefresh);
    if (refresh == null || refresh.isEmpty) return null;
    try {
      _session = await _auth.restore(refresh);
      await _remember(_session!);
      return _session;
    } on CloudException catch (e) {
      debugPrint('Renovação da sessão: $e');
      // conta apagada, desativada ou senha trocada: pede o login de novo
      if (e.status == 400) {
        error = authMessage(e);
        await signOut();
      }
      return null;
    } catch (e) {
      debugPrint('Renovação da sessão: $e');
      return null;
    }
  }

  /// Sessão para uso fora da tela (verificação em segundo plano): usa o token
  /// de renovação guardado. Devolve (uid, Firestore) ou null.
  static Future<(String, Firestore)?> background(SharedPreferences prefs) async {
    final refresh = prefs.getString(_kRefresh);
    if (refresh == null || refresh.isEmpty || kFirebaseApiKey.isEmpty || kFirebaseProjectId.isEmpty) return null;
    if (!(prefs.getBool(_kVerified) ?? false)) return null;
    final s = await FirebaseAuthRest(kFirebaseApiKey).restore(refresh);
    await prefs.setString(_kRefresh, s.refreshToken);
    await prefs.setString(_kUid, s.uid);
    return (s.uid, Firestore(kFirebaseProjectId, () async => s.idToken));
  }
}
