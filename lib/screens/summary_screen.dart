import 'package:flutter/material.dart';

import '../models/diary.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/summary_view.dart';

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
        ],
      ),
    );
  }
}

/// Últimas pesagens e variação.
class WeightCard extends StatelessWidget {
  const WeightCard({super.key, required this.weights, this.onAdd});

  final List<WeightRecord> weights;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final recent = weights.reversed.take(5).toList();
    String? change;
    if (weights.length >= 2) {
      final diff = weights.last.kg - weights.first.kg;
      final sign = diff > 0 ? '+' : (diff < 0 ? '−' : '');
      change = '$sign${fmt(diff.abs(), 1)} kg desde ${shortDate(parseDateKey(weights.first.date))}';
    }
    return NvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Peso', style: text.titleMedium)),
              if (onAdd != null) TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Registrar')),
            ],
          ),
          if (weights.isEmpty)
            Text('Nenhuma pesagem registrada.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          else ...[
            Text('${fmt(weights.last.kg, 1)} kg', style: text.headlineMedium),
            if (change != null) Text(change, style: text.bodySmall),
            const SizedBox(height: 8),
            for (final w in recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(friendlyDate(parseDateKey(w.date)))),
                    Text('${fmt(w.kg, 1)} kg', style: text.labelLarge),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
