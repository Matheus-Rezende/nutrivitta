import 'package:flutter/material.dart';

import '../cloud/account.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';

/// Primeira tela: entrar com a conta Google.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final account = Account.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: account,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Center(child: NvLogo(size: 96)),
                const SizedBox(height: 24),
                Text('NutriVitta', textAlign: TextAlign.center, style: text.displaySmall),
                const SizedBox(height: 12),
                Text(
                  'Registre o que comeu e quando comeu, acompanhe calorias e macronutrientes '
                  'e compartilhe o diário com o seu nutricionista.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                if (account.error != null) ...[
                  Text(account.error!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: scheme.error)),
                  const SizedBox(height: 12),
                ],
                if (account.supported)
                  FilledButton.icon(
                    onPressed: account.busy ? null : () => account.signIn(),
                    icon: account.busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: const Text('Entrar com o Google'),
                  )
                else
                  Text(
                    account.googleConfigured
                        ? 'O login com o Google está disponível no Android. Neste aparelho, os dados ficam só aqui.'
                        : 'O login com o Google ainda não foi configurado neste app (veja CONFIGURACAO.md). '
                            'Por enquanto, os dados ficam só neste aparelho.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: account.busy
                      ? null
                      : () => AppScope.read(context).useLocalMode(),
                  child: const Text('Usar sem conta neste aparelho'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Com a conta Google, seus dados ficam salvos online e uma cópia vai para o seu Google Drive.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
