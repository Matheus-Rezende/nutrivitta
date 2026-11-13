import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';
import '../sync.dart';
import 'connections_screen.dart';
import 'onboarding_screen.dart';

/// Cartão da conta: quem está conectado, estado da sincronização e sair.
/// Usado no perfil do paciente e do nutricionista.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  String _when(DateTime? t) => t == null ? 'ainda não feita' : '${friendlyDate(t).toLowerCase()} às ${hourMinute(t)}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final account = Account.instance;
    final sync = Sync.instance;
    final state = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([account, sync]),
      builder: (context, _) {
        if (!account.signedIn) {
          return NvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Conta', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  account.supported
                      ? 'Você não está conectado. Os dados estão só neste aparelho.'
                      : 'Login Google indisponível neste aparelho ou ainda não configurado. Os dados estão só aqui.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (account.error != null) ...[
                  const SizedBox(height: 8),
                  Text(account.error!, style: text.bodySmall?.copyWith(color: scheme.error)),
                ],
                if (account.supported) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: account.busy ? null : () => account.signIn(),
                    icon: const Icon(Icons.login),
                    label: const Text('Entrar com o Google'),
                  ),
                ],
              ],
            ),
          );
        }
        final pending = state.dirty.length;
        return NvCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      account.name.isEmpty ? '?' : account.name.characters.first.toUpperCase(),
                      style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
                    ),
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
              const SizedBox(height: 12),
              _StatusLine(
                icon: account.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                text: account.online
                    ? (pending == 0 ? 'Dados online em dia' : 'Enviando alterações ($pending pendentes)')
                    : (account.firebaseConfigured
                        ? 'Sem conexão com a nuvem do app'
                        : 'Nuvem do app não configurada: só a cópia no Drive está ativa'),
              ),
              _StatusLine(icon: Icons.add_to_drive_outlined, text: 'Cópia no Google Drive: ${_when(sync.lastDriveBackup)}'),
              if (sync.message != null) ...[
                const SizedBox(height: 4),
                Text(sync.message!, style: text.bodySmall),
              ],
              if (account.error != null) ...[
                const SizedBox(height: 4),
                Text(account.error!, style: text.bodySmall?.copyWith(color: scheme.error)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: sync.busy ? null : () => sync.refresh(),
                      icon: sync.busy
                          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync),
                      label: const Text('Sincronizar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await confirm(context,
                            title: 'Sair da conta?',
                            text: 'Os dados continuam salvos online e neste aparelho. Você pode entrar de novo quando quiser.',
                            ok: 'Sair');
                        if (ok) await sync.signOut();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sair'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Crédito da tabela de alimentos e aviso de uso.
class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Text(
        'NutriVitta 0.2.0\n'
        'Valores nutricionais: ${state.foodDb.source}\n'
        'O app ajuda no acompanhamento alimentar e não substitui a consulta com um profissional de saúde.',
        style: text.bodySmall,
      ),
    );
  }
}

/// Perfil do paciente.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editGoals(BuildContext context) async {
    final state = AppScope.read(context);
    final goals = await Navigator.push<Goals>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalsScreen(goals: state.goals, suggestion: state.profile.hasMeasures ? state.profile.suggestGoals() : null),
      ),
    );
    if (goals != null) state.setGoals(goals);
  }

  Future<void> _editAnamnesis(BuildContext context) async {
    final state = AppScope.read(context);
    final a = await Navigator.push<Anamnesis>(
      context,
      MaterialPageRoute(
        builder: (_) => AnamnesisEditScreen(
          anamnesis: state.anamnesis,
          intro: 'Estas respostas ajudam o seu nutricionista a montar o acompanhamento. '
              'Preencha o que souber; dá para completar depois.',
        ),
      ),
    );
    if (a != null) state.setAnamnesis(a);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final g = state.goals;
    final a = state.anamnesis;
    final pending = state.pendingLinks.length;
    final connected = state.connectedLinks;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const AccountCard(),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Badge(
                isLabelVisible: pending > 0,
                label: Text('$pending'),
                child: const Icon(Icons.medical_information_outlined),
              ),
              title: const Text('Nutricionistas'),
              subtitle: Text(pending > 0
                  ? (pending == 1 ? '1 pedido de conexão aguardando você' : '$pending pedidos de conexão aguardando você')
                  : connected.isEmpty
                      ? 'Nenhum nutricionista conectado'
                      : 'Conectado com ${connected.map((l) => l.proName).join(', ')}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Metas diárias'),
                  subtitle: Text(
                      '${fmt(g.kcal)} kcal · P ${fmt(g.protein)} g · C ${fmt(g.carbs)} g · G ${fmt(g.fat)} g'
                      '${g.by.isEmpty ? '' : '\nDefinidas por ${g.by}'}'),
                  isThreeLine: g.by.isNotEmpty,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editGoals(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.name.isEmpty ? 'Meus dados' : p.name),
                  subtitle: Text(p.hasMeasures
                      ? '${fmt(p.weightKg, 1)} kg · ${fmt(p.heightCm)} cm · ${p.activity.label} · ${p.objective.label}'
                      : 'Informe peso e altura para estimar as metas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PatientDataScreen(initial: p))),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: const Text('Anamnese'),
                  subtitle: Text(a.isEmpty
                      ? 'Questionário sobre rotina, alimentação e saúde'
                      : '${a.filled} de ${Anamnesis.total} respostas'
                          '${a.updatedBy.isNotEmpty && a.updatedBy != p.name ? ' · atualizada por ${a.updatedBy}' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editAnamnesis(context),
                ),
              ],
            ),
          ),
          const AboutCard(),
        ],
      ),
    );
  }
}
