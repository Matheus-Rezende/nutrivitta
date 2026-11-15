import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'firebase_rest.dart';

/// Conta do NutriVitta: cadastro e login com e-mail e senha no Firebase
/// Authentication. O app só libera os dados depois que o e-mail é confirmado.
///
/// Quando a senha é trocada (em qualquer aparelho), as sessões abertas antes
/// são encerradas: o app confere com o servidor ao voltar para a frente e a
/// cada [watchEvery], e pede para entrar de novo.
class Account extends ChangeNotifier with WidgetsBindingObserver {
  Account._();

  static final instance = Account._();

  static const _kRefresh = 'nv_fb_refresh_v1';
  static const _kUid = 'nv_fb_uid_v1';
  static const _kEmail = 'nv_fb_email_v1';
  static const _kName = 'nv_fb_name_v1';
  static const _kVerified = 'nv_fb_verified_v1';
  static const _kCredAt = 'nv_fb_cred_at_v1';
  static const _kReauth = 'nv_fb_reauth_v1';

  /// Intervalo da conferência da sessão com o app aberto.
  static const watchEvery = Duration(seconds: 30);

  /// Tamanho mínimo da senha.
  static const minPassword = 8;

  final _auth = FirebaseAuthRest(kFirebaseApiKey);

  FirebaseSession? _session;
  SharedPreferences? _prefs;
  String? _uid;
  String _email = '';
  String _name = '';
  bool _verified = false;
  int _credAt = 0;
  Future<FirebaseSession?>? _restoring;
  bool _observing = false;
  bool _checkingSession = false;
  DateTime? _lastSessionCheck;
  Timer? _watch;

  /// A sessão foi encerrada (senha trocada): mostrar a tela de entrar.
  bool reauth = false;

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
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    reauth = p.getBool(_kReauth) ?? false;
    if (reauth) error = _passwordChanged;
    final refresh = p.getString(_kRefresh);
    if (refresh == null || refresh.isEmpty) return;
    _uid = p.getString(_kUid);
    _email = p.getString(_kEmail) ?? '';
    _name = p.getString(_kName) ?? '';
    _verified = p.getBool(_kVerified) ?? false;
    _credAt = p.getInt(_kCredAt) ?? 0;
    if (_uid == null) return;
    notifyListeners();
    _startWatch();
    unawaited(checkSession(force: true));
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
    await p.setInt(_kCredAt, _credAt);
    await p.setBool(_kReauth, reauth);
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
      _credAt = 0;
      reauth = false;
      await _rememberUser();
      _startWatch();
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
      _credAt = u.credentialsAt;
      reauth = false;
      await _rememberUser();
      _startWatch();
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
      if (_credAt == 0) _credAt = u.credentialsAt;
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
    for (final k in [_kRefresh, _kUid, _kEmail, _kName, _kVerified, _kCredAt, _kReauth]) {
      await p.remove(k);
    }
    _stopWatch();
    final had = _uid != null;
    _session = null;
    _uid = null;
    _email = '';
    _name = '';
    _verified = false;
    _credAt = 0;
    reauth = false;
    error = null;
    if (had) onSignedOut?.call();
    notifyListeners();
  }

  static const _passwordChanged = 'Sua senha foi alterada ou a sessão foi encerrada. Entre de novo com a senha atual.';

  /// Encerra a sessão neste aparelho e pede o login de novo (senha trocada).
  Future<void> _endSession() async {
    if (!signedIn) return;
    await signOut();
    reauth = true;
    error = _passwordChanged;
    await (_prefs ??= await SharedPreferences.getInstance()).setBool(_kReauth, true);
    notifyListeners();
  }

  /// Quem estava usando o app sem conta segue assim, sem entrar de novo.
  Future<void> dismissReauth() async {
    reauth = false;
    error = null;
    await (_prefs ??= await SharedPreferences.getInstance()).remove(_kReauth);
    notifyListeners();
  }

  /// Confere com o servidor se a senha foi trocada depois deste login; se
  /// foi, encerra a sessão. Sem internet, não faz nada.
  Future<void> checkSession({bool force = false}) async {
    if (!signedIn || busy || _checkingSession) return;
    final last = _lastSessionCheck;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 20)) return;
    _checkingSession = true;
    _lastSessionCheck = DateTime.now();
    try {
      final t = await token();
      if (t == null || !signedIn) return;
      final u = await _auth.lookup(t);
      if (_credAt == 0) {
        _credAt = u.credentialsAt;
        await _rememberUser();
      } else if (u.credentialsAt > _credAt) {
        await _endSession();
      }
    } on CloudException catch (e) {
      debugPrint('Conferência da sessão: $e');
      if (e.status == 400) await _endSession();
    } catch (e) {
      debugPrint('Conferência da sessão: $e');
    } finally {
      _checkingSession = false;
    }
  }

  void _startWatch() {
    _watch?.cancel();
    _watch = Timer.periodic(watchEvery, (_) => unawaited(checkSession()));
  }

  void _stopWatch() {
    _watch?.cancel();
    _watch = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && signedIn) {
      _startWatch();
      unawaited(checkSession(force: true));
    } else if (state == AppLifecycleState.paused) {
      _stopWatch();
    }
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
      if (e.status == 400) await _endSession();
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
    if (!(prefs.getBool(_kVerified) ?? false) || (prefs.getBool(_kReauth) ?? false)) return null;
    final s = await FirebaseAuthRest(kFirebaseApiKey).restore(refresh);
    await prefs.setString(_kRefresh, s.refreshToken);
    await prefs.setString(_kUid, s.uid);
    return (s.uid, Firestore(kFirebaseProjectId, () async => s.idToken));
  }
}
