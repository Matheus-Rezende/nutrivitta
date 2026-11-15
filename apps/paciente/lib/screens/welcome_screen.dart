import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';

const _intro = 'Registre o que comeu e quando comeu, acompanhe calorias e macronutrientes '
    'e compartilhe o diário com o seu nutricionista.';

/// Primeira tela: entrar, criar conta ou usar sem conta.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthScreen(
      intro: _intro,
      footer: [
        const Divider(),
        TextButton(
          onPressed: () => AppScope.read(context).useLocalMode(),
          child: const Text('Usar sem conta neste aparelho'),
        ),
        Text(
          'Sem conta, os dados ficam só neste celular e não dá para conectar com nutricionista.',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// Depois da troca de senha: entrar de novo, ou seguir sem conta neste aparelho.
class SignInAgainScreen extends StatelessWidget {
  const SignInAgainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScreen(
      intro: _intro,
      footer: [
        const Divider(),
        TextButton(
          onPressed: () => Account.instance.dismissReauth(),
          child: const Text('Continuar sem conta neste aparelho'),
        ),
      ],
    );
  }
}

/// Entrar ou criar conta a partir do app (quem começou sem conta).
Future<void> openAuth(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AuthScreen(intro: _intro, closeOnSuccess: true)),
  );
}
