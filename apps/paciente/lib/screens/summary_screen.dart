import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';

/// Resumo do paciente: calorias do período e peso.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  int _range = 7;

  Future<void> _addWeight() async {
    final state = AppScope.read(context);
    final ctrl = TextEditingController(text: state.profile.weightKg > 0 ? fmt(state.profile.weightKg, 1) : '');
    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Peso de hoje'),
        content: NumberField(controller: ctrl, label: 'Peso', suffix: 'kg', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseNumber(ctrl.text)), child: const Text('Salvar')),
        ],
      ),
    );
    if (kg == null || !mounted) return;
    if (kg < 20 || kg > 400) {
      showSnack(context, 'Informe o peso em quilos (ex.: 72,5).');
      return;
    }
    state.addWeight(dateKey(DateTime.now()), kg);
  }

  Future<void> _editMeasure(BodyMeasure? initial) async {
    final state = AppScope.read(context);
    final m = await Navigator.push<BodyMeasure>(
      context,
      MaterialPageRoute(builder: (_) => MeasureEditScreen(initial: initial)),
    );
    if (m != null) state.saveMeasure(m);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dates = lastDays(DateTime.now(), _range);
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 dias')),
              ButtonSegment(value: 30, label: Text('30 dias')),
            ],
            selected: {_range},
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: 12),
          SummaryView(dates: dates, days: state.days, goals: state.goals),
          const SizedBox(height: 12),
          WeightCard(weights: state.weights, onAdd: _addWeight),
          const SizedBox(height: 12),
          MeasuresView(
            measures: state.measures,
            onAdd: () => _editMeasure(null),
            onTap: _editMeasure,
          ),
        ],
      ),
    );
  }
}
