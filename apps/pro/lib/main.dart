import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import 'pro_state.dart';
import 'screens/pro_onboarding_screen.dart';
import 'screens/pro_shell.dart';
import 'screens/pro_welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NutriVittaProApp());
}

class NutriVittaProApp extends StatefulWidget {
  const NutriVittaProApp({super.key});

  @override
  State<NutriVittaProApp> createState() => _NutriVittaProAppState();
}

class _NutriVittaProAppState extends State<NutriVittaProApp> {
  late final Future<ProState> _loading = _load();

  static Future<ProState> _load() async {
    final state = await ProState.load();
    final account = Account.instance;
    account.onSignedIn = state.onSignedIn;
    account.onSignedOut = state.onSignedOut;
    await account.init();
    return state;
  }

  MaterialApp _app(Widget home) {
    return MaterialApp(
      title: 'NutriVitta Pro',
      debugShowCheckedModeBanner: false,
      theme: buildNvTheme(Brightness.light, accent: NvColors.teal),
      darkTheme: buildNvTheme(Brightness.dark, accent: NvColors.teal),
      home: home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProState>(
      future: _loading,
      builder: (context, snap) {
        if (!snap.hasData) return _app(const Scaffold(body: Center(child: NvLogo(size: 88))));
        return ProScope(state: snap.data!, child: _app(const _Root()));
      },
    );
  }
}

/// Entrada, cadastro profissional ou o app.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = ProScope.of(context);
    return ListenableBuilder(
      listenable: Account.instance,
      builder: (context, _) {
        final account = Account.instance;
        final Widget screen;
        if (!account.signedIn) {
          screen = const ProWelcomeScreen();
        } else if (state.loadingProfile || account.busy) {
          screen = const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (!state.ready) {
          screen = const ProOnboardingScreen();
        } else {
          screen = const ProShell();
        }
        return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: screen);
      },
    );
  }
}
