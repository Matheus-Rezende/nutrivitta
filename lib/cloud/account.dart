import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import 'drive_backup.dart';
import 'firebase_rest.dart';

/// Conta do NutriVitta: login com o Google, sessão do Firebase (dados online)
/// e autorização do Google Drive (cópia de segurança).
class Account extends ChangeNotifier {
  Account._();

  static final instance = Account._();

  final _auth = FirebaseAuthRest(kFirebaseApiKey);

  GoogleSignInAccount? user;
  FirebaseSession? _session;
  bool _initialized = false;
  Future<void>? _handling;

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

  /// Conectado ao banco online (contas, vínculo paciente e nutricionista).
  bool get online => signedIn && _session != null;

  /// Identificador da conta: o do Firebase, ou o do Google se o Firebase não estiver configurado.
  String? get uid => _session?.uid ?? (user == null ? null : 'g_${user!.id}');

  String get name => user?.displayName ?? '';
  String get email => user?.email ?? '';

  Future<void> init({required bool silent}) async {
    if (!supported || _initialized) return;
    _initialized = true;
    try {
      final g = GoogleSignIn.instance;
      await g.initialize(serverClientId: kGoogleWebClientId);
      g.authenticationEvents.listen(_onAuthEvent, onError: (Object e) {
        debugPrint('Login Google: $e');
      });
      if (silent) unawaited(g.attemptLightweightAuthentication());
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
        error = null;
      } catch (e) {
        debugPrint('Sessão Firebase: $e');
        _session = null;
        error = 'Não foi possível conectar à nuvem do NutriVitta. Seus dados continuam salvos no aparelho.';
      }
    }
    notifyListeners();
  }

  /// Entra com a conta Google e pede acesso à pasta do app no Drive.
  Future<bool> signIn() async {
    if (!supported || busy) return false;
    _setBusy(true);
    error = null;
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const [DriveBackup.scope]);
      await _handle(account);
      try {
        await account.authorizationClient.authorizeScopes(const [DriveBackup.scope]);
      } catch (e) {
        debugPrint('Drive não autorizado: $e');
      }
      _setBusy(false);
      await onSignedIn?.call();
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = 'Não foi possível entrar: ${e.description ?? e.code.name}';
      }
      _setBusy(false);
      return false;
    } catch (e) {
      error = 'Não foi possível entrar: $e';
      _setBusy(false);
      return false;
    }
  }

  /// Sai da conta neste aparelho. Os dados continuam na nuvem.
  Future<void> signOut() async {
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
      return _session!.idToken;
    } catch (e) {
      debugPrint('Renovação da sessão: $e');
      return null;
    }
  }

  /// Acesso à pasta do app no Google Drive; null se a pessoa não autorizou.
  Future<DriveBackup?> drive({bool prompt = false}) async {
    final u = user;
    if (u == null) return null;
    final h = await u.authorizationClient.authorizationHeaders(const [DriveBackup.scope], promptIfNecessary: prompt);
    return h == null ? null : DriveBackup(h);
  }

  void _setBusy(bool b) {
    busy = b;
    notifyListeners();
  }
}
