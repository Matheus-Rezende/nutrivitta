import 'package:flutter/material.dart';

import '../models/diary.dart';
import '../util/format.dart';
import 'common.dart';

/// Edição das metas diárias. Devolve as metas novas ao salvar.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.goals, this.suggestion, this.title = 'Metas diárias'});

  final Goals goals;

  /// Metas estimadas pelas medidas da pessoa (botão "Sugerir").
  final Goals? suggestion;
  final String title;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late final _kcal = TextEditingController(text: fmt(widget.goals.kcal));
  late final _protein = TextEditingController(text: fmt(widget.goals.protein));
  late final _carbs = TextEditingController(text: fmt(widget.goals.carbs));
  late final _fat = TextEditingController(text: fmt(widget.goals.fat));
  late final _water = TextEditingController(text: '${widget.goals.waterMl}');

  @override
  void dispose() {
    for (final c in [_kcal, _protein, _carbs, _fat, _water]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Goals g) {
    setState(() {
      _kcal.text = fmt(g.kcal);
      _protein.text = fmt(g.protein);
      _carbs.text = fmt(g.carbs);
      _fat.text = fmt(g.fat);
      _water.text = '${g.waterMl}';
    });
  }

  double get _macroKcal =>
      (parseNumber(_protein.text) ?? 0) * 4 + (parseNumber(_carbs.text) ?? 0) * 4 + (parseNumber(_fat.text) ?? 0) * 9;

  void _save() {
    final kcal = parseNumber(_kcal.text);
    final protein = parseNumber(_protein.text);
    final carbs = parseNumber(_carbs.text);
    final fat = parseNumber(_fat.text);
    final water = parseNumber(_water.text);
    if (kcal == null || kcal < 500 || protein == null || carbs == null || fat == null || water == null) {
      showSnack(context, 'Preencha todas as metas. As calorias devem ser de pelo menos 500 kcal.');
      return;
    }
    Navigator.pop(context, Goals(kcal: kcal, protein: protein, carbs: carbs, fat: fat, waterMl: water.round()));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NumberField(controller: _kcal, label: 'Calorias', suffix: 'kcal', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: NumberField(controller: _protein, label: 'Proteínas', suffix: 'g', onChanged: (_) => setState(() {}))),
              const SizedBox(width: 12),
              Expanded(child: NumberField(controller: _carbs, label: 'Carboidratos', suffix: 'g', onChanged: (_) => setState(() {}))),
              const SizedBox(width: 12),
              Expanded(child: NumberField(controller: _fat, label: 'Gorduras', suffix: 'g', onChanged: (_) => setState(() {}))),
            ],
          ),
          const SizedBox(height: 8),
          Text('Os macronutrientes somam ${fmt(_macroKcal)} kcal.', style: text.bodySmall),
          const SizedBox(height: 12),
          NumberField(controller: _water, label: 'Água', suffix: 'ml'),
          if (widget.suggestion != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _fill(widget.suggestion!),
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Sugerir pelas medidas'),
            ),
            const SizedBox(height: 8),
            Text(
              'A sugestão usa peso, altura, idade, atividade e objetivo (equação de Mifflin-St Jeor). '
              'É uma estimativa e não substitui a orientação de um nutricionista.',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Salvar metas')),
        ],
      ),
    );
  }
}
