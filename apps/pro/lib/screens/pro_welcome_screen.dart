import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

/// Primeira tela: entrar com a conta Google.
class ProWelcomeScreen extends StatelessWidget {
  const ProWelcomeScreen({super.key});

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
                const Center(child: NvWordmark(size: 40, pro: true)),
                const SizedBox(height: 12),
                Text(
                  'Acompanhe o que seus pacientes comem e quando comem, com fotos das refeições, '
                  'medidas, anamnese, metas e recados.',
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
                        ? 'O NutriVitta Pro funciona no Android com a conta Google.'
                        : 'O login com o Google ainda não foi configurado neste app (veja CONFIGURACAO.md).',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                const SizedBox(height: 12),
                Text(
                  'Seus pacientes usam o app NutriVitta. Eles só aparecem para você depois de aceitar o seu pedido de conexão.',
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
