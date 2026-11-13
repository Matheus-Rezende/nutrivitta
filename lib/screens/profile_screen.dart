import 'package:flutter/material.dart';

import '../cloud/account.dart';
import '../cloud/remote.dart';
import '../cloud/sync.dart';
import '../models/diary.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'goals_screen.dart';
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
        'NutriVitta 0.1.0\n'
        'Valores nutricionais: ${state.foodDb.source}\n'
        'O app ajuda no acompanhamento alimentar e não substitui a consulta com um profissional de saúde.',
        style: text.bodySmall,
      ),
    );
  }
}

/// Perfil do paciente.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _linking = false;

  Future<void> _editGoals() async {
    final state = AppScope.read(context);
    final goals = await Navigator.push<Goals>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalsScreen(goals: state.goals, suggestion: state.profile.hasMeasures ? state.profile.suggestGoals() : null),
      ),
    );
    if (goals != null) state.setGoals(goals);
  }

  Future<void> _link() async {
    final state = AppScope.read(context);
    final account = Account.instance;
    final uid = account.uid;
    if (!account.online || uid == null) {
      showSnack(context, 'Entre com a conta Google para vincular um nutricionista.');
      return;
    }
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código do nutricionista'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(hintText: 'Ex.: K7M2QX', helperText: 'Peça o código de convite ao seu nutricionista.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toUpperCase()), child: const Text('Vincular')),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _linking = true);
    try {
      final found = await Remote.instance.findInvite(code);
      if (!mounted) return;
      if (found == null) {
        showSnack(context, 'Código não encontrado. Confira com o seu nutricionista.');
        return;
      }
      final (nutriUid, nutriName) = found;
      if (nutriUid == uid) {
        showSnack(context, 'Este código é da sua própria conta.');
        return;
      }
      final ok = await confirm(context,
          title: 'Compartilhar com $nutriName?',
          text: '$nutriName poderá ver seu diário alimentar, seu peso e suas medidas, ajustar suas metas e deixar recados. '
              'Você pode desfazer o vínculo quando quiser.',
          ok: 'Compartilhar');
      if (!ok) return;
      // primeiro grava a autorização no próprio perfil; depois entra na lista do nutricionista
      final profile = state.profile.copyWith(
        nutritionistUid: nutriUid,
        nutritionistName: nutriName,
        email: state.profile.email.isEmpty ? account.email : state.profile.email,
      );
      await Remote.instance.saveProfile(uid, profile);
      await Remote.instance.link(uid, profile, nutriUid);
      state.setProfile(profile);
      if (mounted) showSnack(context, 'Diário compartilhado com $nutriName.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível vincular agora. Confira a conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _unlink() async {
    final state = AppScope.read(context);
    final account = Account.instance;
    final uid = account.uid;
    final p = state.profile;
    final ok = await confirm(context,
        title: 'Desfazer o vínculo?', text: '${p.nutritionistName} deixará de ver o seu diário.', ok: 'Desfazer');
    if (!ok || !mounted) return;
    if (!account.online || uid == null) {
      showSnack(context, 'Conecte-se à internet para desfazer o vínculo.');
      return;
    }
    setState(() => _linking = true);
    try {
      final cleared = p.copyWith(nutritionistUid: '', nutritionistName: '');
      await Remote.instance.unlink(uid, p.nutritionistUid);
      await Remote.instance.saveProfile(uid, cleared);
      state.setProfile(cleared);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível desfazer agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = state.profile;
    final g = state.goals;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const AccountCard(),
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
                  onTap: _editGoals,
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          NvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Nutricionista', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  p.hasNutritionist
                      ? 'Seu diário está compartilhado com ${p.nutritionistName}.'
                      : 'Vincule seu nutricionista com o código de convite para que ele acompanhe seu diário.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (_linking)
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                else if (p.hasNutritionist)
                  OutlinedButton.icon(onPressed: _unlink, icon: const Icon(Icons.link_off), label: const Text('Desfazer vínculo'))
                else
                  FilledButton.icon(onPressed: _link, icon: const Icon(Icons.link), label: const Text('Vincular com código')),
              ],
            ),
          ),
          const AboutCard(),
        ],
      ),
    );
  }
}
