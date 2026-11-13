import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/account.dart';
import '../cloud/remote.dart';
import '../state/app_state.dart';
import '../theme/nv_theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'patient_detail_screen.dart';
import 'profile_screen.dart';

/// Abas do nutricionista.
class NutriShell extends StatefulWidget {
  const NutriShell({super.key});

  @override
  State<NutriShell> createState() => _NutriShellState();
}

class _NutriShellState extends State<NutriShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [PatientsScreen(), NutriProfileScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Pacientes'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

/// Lista de pacientes vinculados e o código de convite.
class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _account = Account.instance;
  List<PatientLink>? _patients;
  bool _loading = false;
  bool _failed = false;
  bool _wasOnline = false;

  @override
  void initState() {
    super.initState();
    _account.addListener(_onAccount);
    _wasOnline = _account.online;
    if (_wasOnline) _load();
  }

  @override
  void dispose() {
    _account.removeListener(_onAccount);
    super.dispose();
  }

  void _onAccount() {
    final online = _account.online;
    if (online && !_wasOnline) _load();
    _wasOnline = online;
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final uid = _account.uid;
    if (!_account.online || uid == null || _loading) return;
    _loading = true;
    if (_failed) setState(() => _failed = false);
    try {
      final list = await Remote.instance.patients(uid);
      if (mounted) setState(() => _patients = list);
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _createCode() async {
    final state = AppScope.read(context);
    final uid = _account.uid;
    if (!_account.online || uid == null) return;
    try {
      final code = await Remote.instance.createInvite(uid, state.profile);
      state.setProfile(state.profile.copyWith(inviteCode: code));
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível gerar o código agora.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final code = state.profile.inviteCode;
    final patients = _patients;
    return Scaffold(
      appBar: AppBar(title: const NvWordmark(size: 28)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Seu código de convite', style: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
                    const SizedBox(height: 4),
                    if (code.isEmpty)
                      FilledButton(onPressed: _createCode, child: const Text('Gerar código'))
                    else
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              code,
                              style: TextStyle(
                                fontFamily: display,
                                fontWeight: FontWeight.w800,
                                fontSize: 40,
                                letterSpacing: 6,
                                height: 1.1,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copiar código',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: code));
                              if (context.mounted) showSnack(context, 'Código copiado.');
                            },
                            icon: Icon(Icons.copy, color: scheme.onPrimaryContainer),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'O paciente digita este código em Perfil > Nutricionista para compartilhar o diário com você.',
                      style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SectionTitle('Pacientes', icon: Icons.groups_outlined),
            if (!_account.online)
              const EmptyNote(icon: Icons.cloud_off_outlined, text: 'Entre com a conta Google (aba Perfil) para ver seus pacientes.')
            else if (_failed)
              EmptyNote(
                icon: Icons.error_outline,
                text: 'Não foi possível carregar os pacientes.',
                action: 'Tentar de novo',
                onAction: _load,
              )
            else if (patients == null)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (patients.isEmpty)
              const EmptyNote(
                icon: Icons.person_add_alt,
                text: 'Nenhum paciente vinculado ainda. Passe o seu código de convite e puxe a tela para atualizar.',
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, p) in patients.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.surfaceContainerHighest,
                          child: Text(p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase()),
                        ),
                        title: Text(p.name),
                        subtitle: p.email.isEmpty ? null : Text(p.email),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => PatientDetailScreen(patient: p))),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Perfil do nutricionista.
class NutriProfileScreen extends StatelessWidget {
  const NutriProfileScreen({super.key});

  Future<void> _edit(BuildContext context) async {
    final state = AppScope.read(context);
    final name = TextEditingController(text: state.profile.name);
    final crn = TextEditingController(text: state.profile.crn);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dados profissionais'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            TextField(controller: crn, decoration: const InputDecoration(labelText: 'CRN (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    state.setProfile(state.profile.copyWith(name: name.text.trim(), crn: crn.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
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
              leading: const Icon(Icons.medical_information_outlined),
              title: Text(p.name.isEmpty ? 'Nutricionista' : p.name),
              subtitle: Text(p.crn.isEmpty ? 'CRN não informado' : p.crn),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context),
            ),
          ),
          const AboutCard(),
        ],
      ),
    );
  }
}
