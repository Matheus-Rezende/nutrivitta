import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';
import 'custom_food_screen.dart';
import 'portion_sheet.dart';

/// Busca um alimento e registra no diário.
class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key, required this.at, required this.meal});

  /// Dia e hora sugeridos para o registro.
  final DateTime at;
  final Meal meal;

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _query = TextEditingController();
  int _added = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pick(Food food) async {
    final state = AppScope.read(context);
    final entry = await askPortion(context, food: food, at: widget.at, meal: widget.meal);
    if (entry == null || !mounted) return;
    state.addEntry(entry);
    setState(() => _added++);
    showSnack(context, '${food.name} adicionado em ${entry.meal.label}.');
  }

  Future<void> _newFood() async {
    final food = await Navigator.push<Food>(
      context,
      MaterialPageRoute(builder: (_) => CustomFoodScreen(initialName: _query.text.trim())),
    );
    if (food != null && mounted) await _pick(food);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final q = _query.text.trim();
    final results = q.isEmpty ? const <Food>[] : state.search(q);
    final recents = q.isEmpty ? state.recentFoods() : const <Food>[];
    final mine = q.isEmpty ? state.customFoods : const <Food>[];
    return Scaffold(
      appBar: AppBar(
        title: Text('Adicionar em ${widget.meal.label}'),
        actions: [
          if (_added > 0) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Concluir')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newFood,
        icon: const Icon(Icons.edit_note),
        label: const Text('Novo alimento'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar alimento (ex.: arroz cozido)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar',
                        onPressed: () => setState(_query.clear),
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (q.isEmpty && recents.isEmpty && mine.isEmpty)
                  const EmptyNote(
                    icon: Icons.search,
                    text: 'Digite o nome do alimento. A tabela tem cerca de 600 alimentos brasileiros '
                        '(TACO) e você pode cadastrar os seus pelo rótulo.',
                  ),
                if (q.isNotEmpty && results.isEmpty)
                  EmptyNote(
                    icon: Icons.search_off,
                    text: 'Nada encontrado para "$q".',
                    action: 'Cadastrar este alimento',
                    onAction: _newFood,
                  ),
                if (recents.isNotEmpty) _Header('Usados recentemente', text),
                for (final f in recents) _FoodTile(food: f, onTap: () => _pick(f)),
                if (mine.isNotEmpty) _Header('Meus alimentos', text),
                for (final f in mine)
                  _FoodTile(
                    food: f,
                    onTap: () => _pick(f),
                    onEdit: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomFoodScreen(food: f))),
                  ),
                for (final f in results) _FoodTile(food: f, onTap: () => _pick(f)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label, this.text);

  final String label;
  final TextTheme text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(label, style: text.labelMedium));
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.onTap, this.onEdit});

  final Food food;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final n = food.per100;
    return ListTile(
      onTap: onTap,
      title: Text(food.name),
      subtitle: Text(
          '${food.category} · 100 g: ${fmt(n.kcal)} kcal · P ${fmt(n.protein, 1)} · C ${fmt(n.carbs, 1)} · G ${fmt(n.fat, 1)}'),
      trailing: onEdit == null
          ? const Icon(Icons.add)
          : IconButton(tooltip: 'Editar alimento', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
    );
  }
}
