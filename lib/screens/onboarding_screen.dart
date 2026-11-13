import 'package:flutter/material.dart';

import '../cloud/account.dart';
import '../cloud/remote.dart';
import '../cloud/sync.dart';
import '../models/diary.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// Cadastro inicial: paciente ou nutricionista.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Role? _role;

  @override
  Widget build(BuildContext context) {
    final account = Account.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([Sync.instance, account]),
      builder: (context, _) {
        if (Sync.instance.restoring || account.busy) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Procurando seus dados salvos...')],
              ),
            ),
          );
        }
        final role = _role;
        if (role == null) return _RoleChoice(onPick: (r) => setState(() => _role = r));
        if (role == Role.nutritionist) return _NutritionistForm(onBack: () => setState(() => _role = null));
        return PatientDataScreen(
          initial: Profile(name: account.name, email: account.email),
          onboarding: true,
          onBack: () => setState(() => _role = null),
        );
      },
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({required this.onPick});

  final ValueChanged<Role> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final account = Account.instance;
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const NvWordmark(size: 28),
        actions: [
          if (account.signedIn || state.localMode)
            TextButton(
              onPressed: () async {
                await Sync.instance.signOut();
                await state.wipe();
              },
              child: const Text('Sair'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Como você vai usar o app?', style: text.headlineMedium),
          const SizedBox(height: 16),
          _RoleCard(
            icon: Icons.restaurant_menu,
            title: 'Sou paciente',
            text: 'Registro minhas refeições, acompanho calorias e metas e posso compartilhar com meu nutricionista.',
            onTap: () => onPick(Role.patient),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.medical_information_outlined,
            title: 'Sou nutricionista',
            text: account.online
                ? 'Acompanho o diário dos meus pacientes, defino metas e deixo recados.'
                : 'Disponível com a conta Google e a nuvem do app configurada.',
            onTap: account.online ? () => onPick(Role.nutritionist) : null,
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.title, required this.text, this.onTap});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 36, color: scheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.titleLarge),
                      const SizedBox(height: 4),
                      Text(text, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NutritionistForm extends StatefulWidget {
  const _NutritionistForm({required this.onBack});

  final VoidCallback onBack;

  @override
  State<_NutritionistForm> createState() => _NutritionistFormState();
}

class _NutritionistFormState extends State<_NutritionistForm> {
  late final _name = TextEditingController(text: Account.instance.name);
  final _crn = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _crn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Informe o seu nome.');
      return;
    }
    final account = Account.instance;
    final uid = account.uid;
    if (!account.online || uid == null) {
      showSnack(context, 'Entre com a conta Google para criar o perfil de nutricionista.');
      return;
    }
    final state = AppScope.read(context);
    setState(() => _saving = true);
    try {
      var profile = Profile(role: Role.nutritionist, name: name, email: account.email, crn: _crn.text.trim());
      final code = await Remote.instance.createInvite(uid, profile);
      profile = profile.copyWith(inviteCode: code);
      state.finishOnboarding(profile, const Goals());
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Não foi possível criar o perfil agora. Confira a conexão e tente de novo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: widget.onBack), title: const Text('Perfil de nutricionista')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome (como os pacientes verão)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _crn, decoration: const InputDecoration(labelText: 'CRN (opcional)', hintText: 'Ex.: CRN-3 12345')),
          const SizedBox(height: 12),
          Text('Ao concluir, você recebe um código de convite para passar aos seus pacientes.', style: text.bodySmall),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Concluir'),
          ),
        ],
      ),
    );
  }
}

/// Dados do paciente: usado no cadastro inicial e na edição pelo perfil.
class PatientDataScreen extends StatefulWidget {
  const PatientDataScreen({super.key, required this.initial, this.onboarding = false, this.onBack});

  final Profile initial;
  final bool onboarding;
  final VoidCallback? onBack;

  @override
  State<PatientDataScreen> createState() => _PatientDataScreenState();
}

class _PatientDataScreenState extends State<PatientDataScreen> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _year = TextEditingController(text: widget.initial.birthYear > 0 ? '${widget.initial.birthYear}' : '');
  late final _height = TextEditingController(text: widget.initial.heightCm > 0 ? fmt(widget.initial.heightCm) : '');
  late final _weight = TextEditingController(text: widget.initial.weightKg > 0 ? fmt(widget.initial.weightKg, 1) : '');
  late String _sex = widget.initial.sex;
  late Activity _activity = widget.initial.activity;
  late Objective _objective = widget.initial.objective;

  @override
  void dispose() {
    for (final c in [_name, _year, _height, _weight]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final year = int.tryParse(_year.text.trim()) ?? 0;
    final height = parseNumber(_height.text) ?? 0;
    final weight = parseNumber(_weight.text) ?? 0;
    final now = DateTime.now().year;
    if (name.isEmpty) {
      showSnack(context, 'Informe o seu nome.');
      return;
    }
    if (year < now - 110 || year > now - 5) {
      showSnack(context, 'Informe o ano de nascimento com 4 dígitos.');
      return;
    }
    if (height < 80 || height > 250) {
      showSnack(context, 'Informe a altura em centímetros (ex.: 168).');
      return;
    }
    if (weight < 20 || weight > 400) {
      showSnack(context, 'Informe o peso em quilos (ex.: 72,5).');
      return;
    }
    final state = AppScope.read(context);
    final profile = widget.initial.copyWith(
      role: Role.patient,
      name: name,
      sex: _sex,
      birthYear: year,
      heightCm: height,
      weightKg: weight,
      activity: _activity,
      objective: _objective,
    );
    if (widget.onboarding) {
      state.finishOnboarding(profile, profile.suggestGoals());
    } else {
      state.setProfile(profile);
      if (weight != widget.initial.weightKg) state.addWeight(dateKey(DateTime.now()), weight);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null ? null : BackButton(onPressed: widget.onBack),
        title: Text(widget.onboarding ? 'Sobre você' : 'Meus dados'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.onboarding) ...[
            Text('Com estes dados o app estima suas metas de calorias. Você pode ajustar depois.', style: text.bodyMedium),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 16),
          Text('Sexo (para o cálculo do gasto de energia)', style: text.labelMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'F', label: Text('Feminino')),
              ButtonSegment(value: 'M', label: Text('Masculino')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ano de nascimento'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: NumberField(controller: _height, label: 'Altura', suffix: 'cm')),
              const SizedBox(width: 12),
              Expanded(child: NumberField(controller: _weight, label: 'Peso', suffix: 'kg')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Nível de atividade', style: text.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in Activity.values)
                ChoiceChip(
                  label: Text(a.label),
                  tooltip: a.hint,
                  selected: _activity == a,
                  onSelected: (_) => setState(() => _activity = a),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_activity.hint, style: text.bodySmall),
          const SizedBox(height: 16),
          Text('Objetivo', style: text.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in Objective.values)
                ChoiceChip(
                  label: Text(o.label),
                  selected: _objective == o,
                  onSelected: (_) => setState(() => _objective = o),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(widget.onboarding ? 'Começar' : 'Salvar')),
        ],
      ),
    );
  }
}
