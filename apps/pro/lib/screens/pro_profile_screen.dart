import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../pro_state.dart';
import 'pro_onboarding_screen.dart';

/// Perfil do nutricionista: conta, dados profissionais e sair.
class ProProfileScreen extends StatelessWidget {
  const ProProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = ProScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final account = Account.instance;
    final p = state.profile ?? const ProProfile();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          NvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Text(account.name.isEmpty ? '?' : account.name.characters.first.toUpperCase(),
                          style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(account.name.isEmpty ? 'Conta Google' : account.name, style: text.titleMedium),
                          Text(account.email, style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  account.online ? 'Conectado à nuvem do NutriVitta.' : 'Sem conexão com a nuvem do NutriVitta.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: 'Sair da conta?',
                        text: 'Os dados dos pacientes continuam online. Você pode entrar de novo quando quiser.',
                        ok: 'Sair');
                    if (ok) await account.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.medical_information_outlined),
              title: Text(p.name.isEmpty ? 'Nutricionista' : p.name),
              subtitle: Text(p.crn.isEmpty ? 'CRN não informado' : p.crn),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ProOnboardingScreen(editing: true))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
            child: Text(
              'NutriVitta Pro 0.2.0\n'
              'Valores nutricionais: Tabela Brasileira de Composição de Alimentos (TACO), 4ª edição, NEPA/UNICAMP, 2011.\n'
              'Os dados de alimentação e saúde dos pacientes são sensíveis (LGPD): use-os só para o acompanhamento.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
