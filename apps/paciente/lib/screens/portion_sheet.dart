import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';

/// Abre a folha de quantidade para um alimento novo. Devolve o registro pronto.
Future<FoodEntry?> askPortion(BuildContext context, {required Food food, required DateTime at, required Meal meal}) {
  return showModalBottomSheet<FoodEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PortionSheet(
      name: food.name,
      foodId: food.id,
      per100: food.per100,
      portionName: food.hasPortion ? food.portionName : null,
      portionGrams: food.portionGrams,
      grams: food.hasPortion ? food.portionGrams : 100,
      at: at,
      meal: meal,
    ),
  );
}

/// Abre a folha para editar um registro existente.
Future<FoodEntry?> editPortion(BuildContext context, FoodEntry entry) {
  final food = AppScope.read(context).food(entry.foodId);
  return showModalBottomSheet<FoodEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PortionSheet(
      entryId: entry.id,
      name: entry.name,
      foodId: entry.foodId,
      per100: entry.per100,
      portionName: food != null && food.hasPortion ? food.portionName : null,
      portionGrams: food?.portionGrams ?? 0,
      grams: entry.grams,
      at: entry.time,
      meal: entry.meal,
      hasPhoto: entry.hasPhoto,
    ),
  );
}

class _PortionSheet extends StatefulWidget {
  const _PortionSheet({
    this.entryId,
    required this.name,
    required this.foodId,
    required this.per100,
    this.portionName,
    this.portionGrams = 0,
    required this.grams,
    required this.at,
    required this.meal,
    this.hasPhoto = false,
  });

  final String? entryId;
  final String name;
  final String foodId;
  final Nutrients per100;
  final String? portionName;
  final double portionGrams;
  final double grams;
  final DateTime at;
  final Meal meal;
  final bool hasPhoto;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  late final _grams = TextEditingController(text: fmt(widget.grams, 1));
  late DateTime _when = widget.at;
  late Meal _meal = widget.meal;

  /// Foto: a que já existia, uma nova escolhida agora (base64) ou nenhuma.
  late bool _hasPhoto = widget.hasPhoto;
  String? _newPhoto;
  bool _picking = false;

  Future<void> _pick(ImageSource source) async {
    setState(() => _picking = true);
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 720, maxHeight: 720, imageQuality: 55);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 600000) {
        if (mounted) showSnack(context, 'A foto ficou grande demais. Tente outra.');
        return;
      }
      setState(() {
        _newPhoto = base64Encode(bytes);
        _hasPhoto = true;
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível abrir a câmera ou a galeria.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _photoRow(TextTheme text) {
    final scheme = Theme.of(context).colorScheme;
    final photo = _newPhoto;
    return Row(
      children: [
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(base64Decode(photo), width: 56, height: 56, fit: BoxFit.cover),
          )
        else
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
            child: Icon(_hasPhoto ? Icons.photo_outlined : Icons.add_a_photo_outlined, color: scheme.onSurfaceVariant),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(_hasPhoto ? 'Foto anexada' : 'Foto da refeição (opcional)', style: text.bodyMedium),
        ),
        if (_picking)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          IconButton(
              tooltip: 'Tirar foto', onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined)),
          IconButton(
              tooltip: 'Escolher da galeria',
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined)),
          if (_hasPhoto)
            IconButton(
              tooltip: 'Remover foto',
              onPressed: () => setState(() {
                _hasPhoto = false;
                _newPhoto = null;
              }),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double get _g => parseNumber(_grams.text) ?? 0;

  void _setGrams(double g) => setState(() => _grams.text = fmt(g, 1));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day + 1),
      helpText: 'Dia em que comeu',
    );
    if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
      helpText: 'Hora em que comeu',
    );
    if (t == null) return;
    setState(() {
      final old = Meal.forTime(_when);
      _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute);
      // se a refeição ainda era a sugerida pelo horário, acompanha a hora nova
      if (_meal == old) _meal = Meal.forTime(_when);
    });
  }

  void _save() {
    final g = _g;
    if (g <= 0 || g > 5000) {
      showSnack(context, 'Informe a quantidade em gramas.');
      return;
    }
    final state = AppScope.read(context);
    final id = widget.entryId ?? state.newId();
    if (_newPhoto != null) {
      state.setPhoto(id, _newPhoto!);
    } else if (widget.hasPhoto && !_hasPhoto) {
      state.removePhoto(id);
    }
    Navigator.pop(
      context,
      FoodEntry(
        id: id,
        time: _when,
        meal: _meal,
        foodId: widget.foodId,
        name: widget.name,
        grams: g,
        nutrients: widget.per100.scale(g / 100),
        hasPhoto: _hasPhoto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final n = widget.per100.scale(_g / 100);
    final portion = widget.portionName;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.name, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Por 100 g: ${fmt(widget.per100.kcal)} kcal · P ${fmt(widget.per100.protein, 1)} · '
                'C ${fmt(widget.per100.carbs, 1)} · G ${fmt(widget.per100.fat, 1)}',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              NumberField(controller: _grams, label: 'Quantidade', suffix: 'g', onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (portion != null)
                    for (final k in const [1, 2])
                      ActionChip(
                        label: Text(k == 1 ? portion : '2 × $portion'),
                        onPressed: () => _setGrams(widget.portionGrams * k),
                      ),
                  for (final g in const [50.0, 100.0, 150.0, 200.0, 300.0])
                    ActionChip(label: Text('${fmt(g)} g'), onPressed: () => _setGrams(g)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _Value(fmt(n.kcal), 'kcal')),
                    Expanded(child: _Value(fmt(n.protein, 1), 'proteínas (g)')),
                    Expanded(child: _Value(fmt(n.carbs, 1), 'carbos (g)')),
                    Expanded(child: _Value(fmt(n.fat, 1), 'gorduras (g)')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Quando comeu', style: text.labelMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(friendlyDate(_when)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(hourMinute(_when)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Refeição', style: text.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in Meal.values)
                    ChoiceChip(label: Text(m.label), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
                ],
              ),
              const SizedBox(height: 16),
              _photoRow(text),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: Text(widget.entryId == null ? 'Adicionar ao diário' : 'Salvar')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [Text(value, style: text.titleLarge), Text(label, textAlign: TextAlign.center, style: text.bodySmall)],
    );
  }
}
