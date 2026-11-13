import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';
import '../sync.dart';

/// Cadastro inicial do paciente (ou espera enquanto procura dados salvos).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

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
        final state = AppScope.of(context);
        return PatientDataScreen(
          initial: Profile(name: account.name, email: account.email),
          onboarding: true,
          onBack: () async {
            await Sync.instance.signOut();
            await state.wipe();
          },
        );
      },
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
        automaticallyImplyLeading: !widget.onboarding,
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
