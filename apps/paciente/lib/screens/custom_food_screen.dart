import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';

/// Cadastro de um alimento próprio (valores do rótulo, por 100 g).
/// Devolve o alimento salvo.
class CustomFoodScreen extends StatefulWidget {
  const CustomFoodScreen({super.key, this.food, this.initialName = ''});

  final Food? food;
  final String initialName;

  @override
  State<CustomFoodScreen> createState() => _CustomFoodScreenState();
}

class _CustomFoodScreenState extends State<CustomFoodScreen> {
  late final _name = TextEditingController(text: widget.food?.name ?? widget.initialName);
  late final _kcal = _num(widget.food?.per100.kcal);
  late final _protein = _num(widget.food?.per100.protein);
  late final _carbs = _num(widget.food?.per100.carbs);
  late final _fat = _num(widget.food?.per100.fat);
  late final _fiber = _num(widget.food?.per100.fiber);
  late final _portionName = TextEditingController(text: widget.food?.portionName ?? '');
  late final _portionGrams = _num((widget.food?.portionGrams ?? 0) > 0 ? widget.food!.portionGrams : null);

  static TextEditingController _num(double? v) => TextEditingController(text: v == null ? '' : fmt(v, 1));

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _fiber, _portionName, _portionGrams]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final kcal = parseNumber(_kcal.text);
    if (name.isEmpty || kcal == null) {
      showSnack(context, 'Informe o nome e as calorias por 100 g.');
      return;
    }
    final state = AppScope.read(context);
    final food = Food(
      id: widget.food?.id ?? 'meu:${state.newId()}',
      name: name,
      category: 'Meus alimentos',
      custom: true,
      per100: Nutrients(
        kcal: kcal,
        protein: parseNumber(_protein.text) ?? 0,
        carbs: parseNumber(_carbs.text) ?? 0,
        fat: parseNumber(_fat.text) ?? 0,
        fiber: parseNumber(_fiber.text) ?? 0,
      ),
      portionName: _portionName.text.trim(),
      portionGrams: parseNumber(_portionGrams.text) ?? 0,
    );
    state.saveCustomFood(food);
    Navigator.pop(context, food);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.food == null ? 'Novo alimento' : 'Editar alimento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Iogurte natural da marca X'),
          ),
          const SizedBox(height: 16),
          Text('Valores por 100 g (ou 100 ml), como no rótulo', style: text.labelMedium),
          const SizedBox(height: 8),
          NumberField(controller: _kcal, label: 'Calorias', suffix: 'kcal'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: NumberField(controller: _protein, label: 'Proteínas', suffix: 'g')),
              const SizedBox(width: 12),
              Expanded(child: NumberField(controller: _carbs, label: 'Carboidratos', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: NumberField(controller: _fat, label: 'Gorduras', suffix: 'g')),
              const SizedBox(width: 12),
              Expanded(child: NumberField(controller: _fiber, label: 'Fibras', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Medida caseira (opcional)', style: text.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _portionName,
                  decoration: const InputDecoration(labelText: 'Medida', hintText: 'Ex.: 1 pote, 1 fatia'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: NumberField(controller: _portionGrams, label: 'Peso', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Salvar alimento')),
        ],
      ),
    );
  }
}
