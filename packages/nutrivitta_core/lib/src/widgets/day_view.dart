import 'package:flutter/material.dart';

import '../models/diary.dart';
import '../theme/nv_theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'photo_view.dart';

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
    this.loadPhoto,
    this.onMealPhoto,
    this.photoCacheScope = '',
    this.onDeleteComment,
  });

  final DayLog day;
  final Goals goals;
  final DayComment? comment;
  final ValueChanged<Meal>? onAdd;
  final ValueChanged<FoodEntry>? onTapEntry;
  final ValueChanged<FoodEntry>? onDeleteEntry;
  final ValueChanged<int>? onWater;

  /// Busca a foto do prato de uma refeição (JPEG em base64). Sem ela, as
  /// fotos não aparecem.
  final Future<String?> Function(Meal meal)? loadPhoto;

  /// Botão de câmera no cabeçalho de cada refeição (só no app do paciente).
  final ValueChanged<Meal>? onMealPhoto;

  /// Distingue as fotos guardadas em memória (ex.: o uid do paciente).
  final String photoCacheScope;

  /// Botão para apagar o recado (só no app do paciente).
  final ValueChanged<DayComment>? onDeleteComment;

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
                  if (onDeleteComment != null)
                    IconButton(
                      tooltip: 'Apagar recado',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onDeleteComment!(comment!),
                      icon: Icon(Icons.close_rounded, color: scheme.onPrimaryContainer),
                    ),
                ],
              ),
            ),
          ),
        ],
        for (final meal in Meal.values)
          if (!readOnly || day.of(meal).isNotEmpty || day.hasPhoto(meal)) ...[
            const SizedBox(height: 12),
            _MealCard(
              day: day,
              meal: meal,
              onAdd: onAdd,
              onTapEntry: onTapEntry,
              onDeleteEntry: onDeleteEntry,
              loadPhoto: loadPhoto,
              onMealPhoto: onMealPhoto,
              photoCacheScope: photoCacheScope,
            ),
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
  const _MealCard({
    required this.day,
    required this.meal,
    this.onAdd,
    this.onTapEntry,
    this.onDeleteEntry,
    this.loadPhoto,
    this.onMealPhoto,
    this.photoCacheScope = '',
  });

  final DayLog day;
  final Meal meal;
  final ValueChanged<Meal>? onAdd;
  final ValueChanged<FoodEntry>? onTapEntry;
  final ValueChanged<FoodEntry>? onDeleteEntry;
  final Future<String?> Function(Meal meal)? loadPhoto;
  final ValueChanged<Meal>? onMealPhoto;
  final String photoCacheScope;

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
                if (onMealPhoto != null)
                  IconButton(
                    tooltip: day.hasPhoto(meal) ? 'Foto do prato' : 'Tirar foto do prato',
                    onPressed: () => onMealPhoto!(meal),
                    icon: Icon(day.hasPhoto(meal) ? Icons.photo_camera : Icons.add_a_photo_outlined),
                  ),
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
          if (day.hasPhoto(meal) && loadPhoto != null) _photo(context),
          for (final e in entries) ...[
            const Divider(),
            _EntryTile(entry: e, onTap: onTapEntry, onDelete: onDeleteEntry),
          ],
        ],
      ),
    );
  }
}

extension on _MealCard {
  /// Foto do prato: miniatura; toque para ver inteira, com zoom.
  Widget _photo(BuildContext context) {
    final key = '$photoCacheScope/${day.photoIdOf(meal)}/${day.photos[meal]}';
    Future<String?> load() => loadPhoto!(meal);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          child: InkWell(
            onTap: () => showMealPhoto(context, title: '${meal.label} · ${friendlyDate(DateTime.parse(day.date))}',
                load: load, cacheKey: key),
            child: MealPhoto(key: ValueKey(key), load: load, cacheKey: key, height: 180),
          ),
        ),
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
