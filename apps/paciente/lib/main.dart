import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import 'background.dart';
import 'screens/onboarding_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/welcome_screen.dart';
import 'state/app_state.dart';
import 'sync.dart';
import 'version.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NutriVittaApp());
}

class NutriVittaApp extends StatefulWidget {
  const NutriVittaApp({super.key});

  @override
  State<NutriVittaApp> createState() => _NutriVittaAppState();
}

class _NutriVittaAppState extends State<NutriVittaApp> {
  late Future<AppState> _loading = _load();

  static Future<AppState> _load() async {
    Updater.app = kApp;
    await AppSettings.load(defaultAccent: Accent.green);
    final state = await AppState.load();
    await Sync.instance.init(state);
    await Background.instance.init();
    return state;
  }

  /// Antes de carregar as preferências (abertura e erro).
  Widget _plain(Widget home) => MaterialApp(
        title: 'NutriVitta',
        debugShowCheckedModeBanner: false,
        theme: buildNvTheme(Brightness.light),
        darkTheme: buildNvTheme(Brightness.dark),
        home: home,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _loading,
      builder: (context, snap) {
        if (snap.hasError) {
          return _plain(_LoadError(
            message: '${snap.error}',
            onRetry: () => setState(() => _loading = _load()),
          ));
        }
        if (!snap.hasData) return _plain(const _Splash());
        final s = AppSettings.instance;
        return AppScope(
          state: snap.data!,
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) => MaterialApp(
              title: 'NutriVitta',
              debugShowCheckedModeBanner: false,
              navigatorKey: updateNavigatorKey,
              theme: s.lightTheme(),
              darkTheme: s.darkTheme(),
              themeMode: s.themeMode,
              builder: (context, child) => s.applyTextScale(context, UpdateProgressBanner(child: child!)),
              home: const UpdateWatcher(child: _Root()),
            ),
          ),
        );
      },
    );
  }
}

/// Decide a tela: entrada, confirmação do e-mail, cadastro ou o app.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: Account.instance,
      builder: (context, _) {
        final account = Account.instance;
        final Widget screen;
        if (account.signedIn && !account.verified) {
          screen = const VerifyEmailScreen();
        } else if (state.onboarded) {
          screen = const PatientShell();
        } else if (account.signedIn || state.localMode) {
          screen = const OnboardingScreen();
        } else {
          screen = const WelcomeScreen();
        }
        return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: screen);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: NvLogo(size: 88)));
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Não foi possível abrir os dados do app.'),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      ),
    );
  }
}
