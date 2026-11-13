import 'package:flutter/material.dart';

import '../cloud/sync.dart';
import '../models/diary.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/day_view.dart';
import 'add_food_screen.dart';
import 'portion_sheet.dart';

/// Diário alimentar do paciente.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DateTime _date = dayOnly(DateTime.now());

  bool get _isToday => dateKey(_date) == dateKey(DateTime.now());

  void _shift(int days) => setState(() => _date = DateTime(_date.year, _date.month, _date.day + days));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day + 1),
    );
    if (d != null) setState(() => _date = dayOnly(d));
  }

  /// Hora sugerida: agora, se o dia aberto é hoje; senão, meio-dia do dia aberto.
  DateTime _suggestedTime(Meal? meal) {
    final now = DateTime.now();
    if (_isToday) return now;
    const hours = {
      Meal.breakfast: 7,
      Meal.morningSnack: 10,
      Meal.lunch: 12,
      Meal.afternoonSnack: 16,
      Meal.dinner: 20,
      Meal.supper: 22,
    };
    return DateTime(_date.year, _date.month, _date.day, hours[meal] ?? 12);
  }

  void _add([Meal? meal]) {
    final at = _suggestedTime(meal);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddFoodScreen(at: at, meal: meal ?? Meal.forTime(at))),
    );
  }

  Future<void> _edit(FoodEntry entry) async {
    final state = AppScope.read(context);
    final oldDate = dateKey(entry.time);
    final updated = await editPortion(context, entry);
    if (updated != null) state.updateEntry(oldDate, updated);
  }

  void _delete(FoodEntry entry) {
    final state = AppScope.read(context);
    state.removeEntry(dateKey(entry.time), entry.id);
    showSnack(context, '${entry.name} removido.', action: SnackBarAction(label: 'Desfazer', onPressed: () => state.addEntry(entry)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final key = dateKey(_date);
    return Scaffold(
      appBar: AppBar(title: const NvWordmark(size: 28)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: RefreshIndicator(
        onRefresh: Sync.instance.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            Row(
              children: [
                IconButton(tooltip: 'Dia anterior', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(friendlyDate(_date)),
                  ),
                ),
                IconButton(
                  tooltip: 'Próximo dia',
                  onPressed: _isToday ? null : () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            DayView(
              day: state.day(key),
              goals: state.goals,
              comment: state.comment(key),
              onAdd: _add,
              onTapEntry: _edit,
              onDeleteEntry: _delete,
              onWater: (ml) => state.addWater(key, ml),
            ),
          ],
        ),
      ),
    );
  }
}
