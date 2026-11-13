import 'package:flutter/material.dart';

import '../models/diary.dart';
import '../models/food.dart';
import '../theme/nv_theme.dart';
import '../util/format.dart';
import 'common.dart';

/// Resumo de um período: calorias por dia contra a meta e médias dos macros.
class SummaryView extends StatelessWidget {
  const SummaryView({super.key, required this.dates, required this.days, required this.goals});

  /// Dias do período, do mais antigo ao mais novo (aaaa-mm-dd).
  final List<String> dates;
  final Map<String, DayLog> days;
  final Goals goals;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final logged = [
      for (final d in dates)
        if (days[d] != null && days[d]!.entries.isNotEmpty) days[d]!,
    ];
    final n = logged.length;
    final sum = logged.fold(Nutrients.zero, (a, d) => a + d.total);
    final avg = n == 0 ? Nutrients.zero : sum.scale(1 / n);
    final within = logged.where((d) => goals.kcal > 0 && (d.total.kcal - goals.kcal).abs() <= goals.kcal * 0.1).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NvCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Calorias por dia', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('A linha marca a meta de ${fmt(goals.kcal)} kcal.', style: text.bodySmall),
              const SizedBox(height: 16),
              _Bars(dates: dates, days: days, goal: goals.kcal),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Média diária', value: '${fmt(avg.kcal)} kcal')),
            const SizedBox(width: 12),
            Expanded(child: _Stat(label: 'Dias registrados', value: '$n de ${dates.length}')),
            const SizedBox(width: 12),
            Expanded(child: _Stat(label: 'Dentro da meta', value: n == 0 ? '-' : '$within de $n')),
          ],
        ),
        const SizedBox(height: 12),
        NvCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Média dos macronutrientes', style: text.titleMedium),
              const SizedBox(height: 12),
              if (n == 0)
                Text('Sem registros neste período.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
              else
                Row(
                  children: [
                    Expanded(child: MacroBar(label: 'Proteínas', value: avg.protein, goal: goals.protein, color: NvColors.protein)),
                    const SizedBox(width: 12),
                    Expanded(child: MacroBar(label: 'Carboidratos', value: avg.carbs, goal: goals.carbs, color: NvColors.carbs)),
                    const SizedBox(width: 12),
                    Expanded(child: MacroBar(label: 'Gorduras', value: avg.fat, goal: goals.fat, color: NvColors.fat)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return NvCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: text.titleLarge)),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.dates, required this.days, required this.goal});

  final List<String> dates;
  final Map<String, DayLog> days;
  final double goal;

  static const _height = 140.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final values = [for (final d in dates) days[d]?.total.kcal ?? 0.0];
    var top = goal * 1.25;
    for (final v in values) {
      if (v > top) top = v;
    }
    if (top <= 0) top = 1;
    final few = dates.length <= 10;
    final step = few ? 1 : 5;
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in values)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: few ? 5 : 1.5),
                        child: Container(
                          height: v <= 0 ? 3 : (_height * v / top).clamp(3.0, _height).toDouble(),
                          decoration: BoxDecoration(
                            color: v <= 0
                                ? scheme.surfaceContainerHighest
                                : (goal > 0 && v > goal * 1.1 ? NvColors.orange : scheme.primary),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (goal > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _height * goal / top,
                  child: Container(height: 2, color: scheme.onSurface.withValues(alpha: 0.55)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, d) in dates.indexed)
              Expanded(
                child: Text(
                  few
                      ? weekdayShort(parseDateKey(d))
                      : ((dates.length - 1 - i) % step == 0 ? '${parseDateKey(d).day}' : ''),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: text.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
