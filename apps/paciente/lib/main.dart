import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import 'background.dart';
import 'screens/onboarding_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/welcome_screen.dart';
import 'state/app_state.dart';
import 'sync.dart';

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
    final state = await AppState.load();
    await Sync.instance.init(state);
    await Background.instance.init();
    return state;
  }

  MaterialApp _app(Widget home) {
    return MaterialApp(
      title: 'NutriVitta',
      debugShowCheckedModeBanner: false,
      theme: buildNvTheme(Brightness.light),
      darkTheme: buildNvTheme(Brightness.dark),
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _loading,
      builder: (context, snap) {
        if (snap.hasError) {
          return _app(_LoadError(
            message: '${snap.error}',
            onRetry: () => setState(() => _loading = _load()),
          ));
        }
        if (!snap.hasData) return _app(const _Splash());
        return AppScope(state: snap.data!, child: _app(const _Root()));
      },
    );
  }
}

/// Decide a tela: entrada, cadastro ou o app.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: Account.instance,
      builder: (context, _) {
        final Widget screen;
        if (state.onboarded) {
          screen = const PatientShell();
        } else if (Account.instance.signedIn || state.localMode) {
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
