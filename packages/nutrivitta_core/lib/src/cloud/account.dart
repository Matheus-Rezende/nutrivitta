import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'drive_backup.dart';
import 'firebase_rest.dart';

/// Conta do NutriVitta: login com o Google e sessão do Firebase.
/// O app do paciente também pede acesso à pasta do app no Google Drive.
class Account extends ChangeNotifier {
  Account._();

  static final instance = Account._();

  static const _kRefresh = 'nv_fb_refresh_v1';
  static const _kUid = 'nv_fb_uid_v1';
  static const _kAuto = 'nv_auto_signin_v1';

  final _auth = FirebaseAuthRest(kFirebaseApiKey);

  GoogleSignInAccount? user;
  FirebaseSession? _session;
  SharedPreferences? _prefs;
  bool _initialized = false;
  Future<void>? _handling;

  /// Escopos extras pedidos no login (ex.: Google Drive no app do paciente).
  List<String> scopes = const [];

  bool busy = false;
  String? error;

  /// Chamado quando a conta entra (login manual ou silencioso ao abrir o app).
  Future<void> Function()? onSignedIn;

  /// Chamado quando a conta sai.
  VoidCallback? onSignedOut;

  bool get googleConfigured => kGoogleWebClientId.isNotEmpty;
  bool get firebaseConfigured => kFirebaseApiKey.isNotEmpty && kFirebaseProjectId.isNotEmpty;

  /// Login disponível neste aparelho (Android com o cliente configurado).
  bool get supported => !kIsWeb && Platform.isAndroid && googleConfigured;

  bool get signedIn => user != null;

  /// Conectado ao banco online.
  bool get online => signedIn && _session != null;

  /// Identificador da conta: o do Firebase, ou o do Google se o Firebase não estiver configurado.
  String? get uid => _session?.uid ?? (user == null ? null : 'g_${user!.id}');

  String get name => user?.displayName ?? '';
  String get email => (user?.email ?? '').toLowerCase();

  /// Tentar o login silencioso ao abrir o app (desligado quando a pessoa sai da conta).
  bool get autoSignIn => _prefs?.getBool(_kAuto) ?? false;

  Future<void> init({List<String> scopes = const []}) async {
    this.scopes = scopes;
    _prefs ??= await SharedPreferences.getInstance();
    if (!supported || _initialized) return;
    _initialized = true;
    try {
      final g = GoogleSignIn.instance;
      await g.initialize(serverClientId: kGoogleWebClientId);
      g.authenticationEvents.listen(_onAuthEvent, onError: (Object e) {
        debugPrint('Login Google: $e');
      });
      if (autoSignIn) unawaited(g.attemptLightweightAuthentication());
    } catch (e) {
      debugPrint('Falha ao iniciar o login Google: $e');
    }
  }

  Future<void> _onAuthEvent(GoogleSignInAuthenticationEvent event) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(user: final account):
        // durante o login manual, signIn() cuida de tudo
        if (busy) return;
        await _handle(account);
        await onSignedIn?.call();
      case GoogleSignInAuthenticationEventSignOut():
        _clear();
    }
  }

  /// Guarda a conta e abre a sessão no Firebase (uma vez por conta).
  Future<void> _handle(GoogleSignInAccount account) {
    if (user?.id == account.id && (_session != null || !firebaseConfigured)) return Future.value();
    return _handling ??= _open(account).whenComplete(() => _handling = null);
  }

  Future<void> _open(GoogleSignInAccount account) async {
    user = account;
    if (firebaseConfigured) {
      try {
        final idToken = account.authentication.idToken;
        if (idToken == null) throw StateError('O Google não devolveu o token de identidade.');
        _session = await _auth.signInWithGoogle(idToken);
        await _remember(_session!);
        error = null;
      } catch (e) {
        debugPrint('Sessão Firebase: $e');
        _session = null;
        error = 'Não foi possível conectar à nuvem do NutriVitta. Confira a internet e tente de novo.';
      }
    }
    await _prefs?.setBool(_kAuto, true);
    notifyListeners();
  }

  Future<void> _remember(FirebaseSession s) async {
    await _prefs?.setString(_kRefresh, s.refreshToken);
    await _prefs?.setString(_kUid, s.uid);
  }

  /// Entra com a conta Google (e pede os escopos extras, se houver).
  Future<bool> signIn() async {
    if (!supported || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      await _handle(account);
      if (scopes.isNotEmpty) {
        try {
          await account.authorizationClient.authorizeScopes(scopes);
        } catch (e) {
          debugPrint('Escopos não autorizados: $e');
        }
      }
      busy = false;
      notifyListeners();
      await onSignedIn?.call();
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = 'Não foi possível entrar: ${e.description ?? e.code.name}';
      }
    } catch (e) {
      error = 'Não foi possível entrar: $e';
    }
    busy = false;
    notifyListeners();
    return false;
  }

  /// Sai da conta neste aparelho. Os dados continuam na nuvem.
  Future<void> signOut() async {
    await _prefs?.setBool(_kAuto, false);
    await _prefs?.remove(_kRefresh);
    await _prefs?.remove(_kUid);
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _clear();
  }

  void _clear() {
    if (user == null && _session == null) return;
    user = null;
    _session = null;
    onSignedOut?.call();
    notifyListeners();
  }

  /// Token da sessão do Firebase, renovado quando está para vencer.
  Future<String?> token() async {
    final s = _session;
    if (s == null) return null;
    if (s.valid) return s.idToken;
    try {
      _session = await _auth.refresh(s);
      await _remember(_session!);
      return _session!.idToken;
    } catch (e) {
      debugPrint('Renovação da sessão: $e');
      return null;
    }
  }

  /// Acesso à pasta do app no Google Drive; null se a pessoa não autorizou.
  Future<DriveBackup?> drive({bool prompt = false}) async {
    final u = user;
    if (u == null || !scopes.contains(DriveBackup.scope)) return null;
    final h = await u.authorizationClient.authorizationHeaders(const [DriveBackup.scope], promptIfNecessary: prompt);
    return h == null ? null : DriveBackup(h);
  }

  /// Sessão para uso fora da tela (verificação em segundo plano): usa o token
  /// de renovação guardado. Devolve (uid, Firestore) ou null.
  static Future<(String, Firestore)?> background(SharedPreferences prefs) async {
    final refresh = prefs.getString(_kRefresh);
    if (refresh == null || refresh.isEmpty || kFirebaseApiKey.isEmpty || kFirebaseProjectId.isEmpty) return null;
    final s = await FirebaseAuthRest(kFirebaseApiKey).restore(refresh);
    await prefs.setString(_kRefresh, s.refreshToken);
    await prefs.setString(_kUid, s.uid);
    return (s.uid, Firestore(kFirebaseProjectId, () async => s.idToken));
  }
}
