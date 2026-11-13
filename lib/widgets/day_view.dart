import 'package:flutter/material.dart';

import '../models/diary.dart';
import '../theme/nv_theme.dart';
import '../util/format.dart';
import 'common.dart';

/// Resumo e refeições de um dia. Usado no diário do paciente e, só para
/// leitura, na tela do nutricionista.
class DayView extends StatelessWidget {
  const DayView({
    super.key,
    required this.day,
    required this.goals,
    this.comment,
    this.onAdd,
    this.onTapEntry,
    this.onDeleteEntry,
    this.onWater,
  });

  final DayLog day;
  final Goals goals;
  final DayComment? comment;
  final ValueChanged<Meal>? onAdd;
  final ValueChanged<FoodEntry>? onTapEntry;
  final ValueChanged<FoodEntry>? onDeleteEntry;
  final ValueChanged<int>? onWater;

  bool get readOnly => onAdd == null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = day.total;
    final left = goals.kcal - total.kcal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NvCard(
          child: Column(
            children: [
              Row(
                children: [
                  CalorieRing(kcal: total.kcal, goal: goals.kcal),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(left >= 0 ? 'Restam' : 'Passou', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        Text('${fmt(left.abs())} kcal',
                            style: text.headlineMedium?.copyWith(color: left >= 0 ? scheme.onSurface : NvColors.orange)),
                        const SizedBox(height: 8),
                        Text('Fibras: ${fmtG(total.fiber)}', style: text.bodySmall),
                        if (goals.by.isNotEmpty) Text('Metas definidas por ${goals.by}', style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: MacroBar(label: 'Proteínas', value: total.protein, goal: goals.protein, color: NvColors.protein)),
                  const SizedBox(width: 12),
                  Expanded(child: MacroBar(label: 'Carboidratos', value: total.carbs, goal: goals.carbs, color: NvColors.carbs)),
                  const SizedBox(width: 12),
                  Expanded(child: MacroBar(label: 'Gorduras', value: total.fat, goal: goals.fat, color: NvColors.fat)),
                ],
              ),
            ],
          ),
        ),
        if (comment != null) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chat_bubble_outline, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(comment!.author.isEmpty ? 'Recado do nutricionista' : 'Recado de ${comment!.author}',
                            style: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
                        const SizedBox(height: 4),
                        Text(comment!.text, style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        for (final meal in Meal.values)
          if (!readOnly || day.of(meal).isNotEmpty) ...[
            const SizedBox(height: 12),
            _MealCard(day: day, meal: meal, onAdd: onAdd, onTapEntry: onTapEntry, onDeleteEntry: onDeleteEntry),
          ],
        if (readOnly && day.entries.isEmpty)
          const EmptyNote(icon: Icons.no_meals_outlined, text: 'Nenhum alimento registrado neste dia.'),
        const SizedBox(height: 12),
        _WaterCard(ml: day.waterMl, goal: goals.waterMl, onWater: onWater),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.day, required this.meal, this.onAdd, this.onTapEntry, this.onDeleteEntry});

  final DayLog day;
  final Meal meal;
  final ValueChanged<Meal>? onAdd;
  final ValueChanged<FoodEntry>? onTapEntry;
  final ValueChanged<FoodEntry>? onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final entries = day.of(meal);
    final kcal = day.totalOf(meal).kcal;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(meal.icon, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(meal.label, style: text.titleMedium)),
                if (entries.isNotEmpty) Text('${fmt(kcal)} kcal', style: text.labelLarge),
                if (onAdd != null)
                  IconButton(
                    tooltip: 'Adicionar em ${meal.label}',
                    onPressed: () => onAdd!(meal),
                    icon: const Icon(Icons.add_circle_outline),
                  )
                else
                  const SizedBox(width: 8, height: 48),
              ],
            ),
          ),
          for (final e in entries) ...[
            const Divider(),
            _EntryTile(entry: e, onTap: onTapEntry, onDelete: onDeleteEntry),
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, this.onTap, this.onDelete});

  final FoodEntry entry;
  final ValueChanged<FoodEntry>? onTap;
  final ValueChanged<FoodEntry>? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = entry.nutrients;
    final tile = ListTile(
      onTap: onTap == null ? null : () => onTap!(entry),
      title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${hourMinute(entry.time)} · ${fmt(entry.grams)} g · P ${fmt(n.protein)} · C ${fmt(n.carbs)} · G ${fmt(n.fat)}'),
      trailing: Text('${fmt(n.kcal)} kcal', style: text.labelLarge),
    );
    if (onDelete == null) return tile;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: NvColors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete!(entry),
      child: tile,
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.ml, required this.goal, this.onWater});

  final int ml;
  final int goal;
  final ValueChanged<int>? onWater;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ratio = goal <= 0 ? 0.0 : (ml / goal).clamp(0.0, 1.0).toDouble();
    return NvCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.water_drop_outlined, color: NvColors.water),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Água: ${fmt(ml)} de ${fmt(goal)} ml', style: text.titleSmall),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: ratio, minHeight: 8, color: NvColors.water, backgroundColor: scheme.surfaceContainerHighest),
                ),
              ],
            ),
          ),
          if (onWater != null) ...[
            IconButton(
              tooltip: 'Tirar um copo (200 ml)',
              onPressed: ml <= 0 ? null : () => onWater!(-200),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              tooltip: 'Somar um copo (200 ml)',
              onPressed: () => onWater!(200),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ] else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
