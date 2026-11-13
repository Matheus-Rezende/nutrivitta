import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrivitta/cloud/firebase_rest.dart';
import 'package:nutrivitta/main.dart';
import 'package:nutrivitta/models/diary.dart';
import 'package:nutrivitta/models/food.dart';
import 'package:nutrivitta/state/app_state.dart';
import 'package:nutrivitta/util/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FoodEntry _entry(String id, DateTime time, Meal meal, double grams, Nutrients per100) => FoodEntry(
    id: id, time: time, meal: meal, foodId: 'taco:1', name: 'Teste', grams: grams, nutrients: per100.scale(grams / 100));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formatação brasileira', () {
    expect(fmt(12.5, 1), '12,5');
    expect(fmt(12.0, 1), '12');
    expect(fmt(1234.4), '1234');
    expect(parseNumber('72,5'), 72.5);
    expect(parseNumber('abc'), isNull);
    expect(dateKey(DateTime(2026, 3, 7)), '2026-03-07');
    expect(parseDateKey('2026-03-07'), DateTime(2026, 3, 7));
    expect(normalize('Feijão, carioca, cozido'), 'feijao, carioca, cozido');
  });

  test('tabela TACO carrega e a busca encontra alimentos', () {
    final db = FoodDb.parse(File('assets/foods.json').readAsStringSync());
    expect(db.foods.length, greaterThan(500));
    final arroz = db.search('arroz cozido');
    expect(arroz, isNotEmpty);
    expect(arroz.first.name.toLowerCase(), contains('arroz'));
    expect(db.search('feijao carioca'), isNotEmpty);
    final integral = db.byId('taco:1')!;
    expect(integral.per100.kcal, closeTo(124, 0.5));
    expect(integral.forGrams(150).kcal, closeTo(186, 1));
  });

  test('totais do dia e das refeições', () {
    const per100 = Nutrients(kcal: 200, protein: 10, carbs: 20, fat: 5, fiber: 2);
    final day = DayLog('2026-11-13', entries: [
      _entry('a', DateTime(2026, 11, 13, 7, 30), Meal.breakfast, 100, per100),
      _entry('b', DateTime(2026, 11, 13, 12, 15), Meal.lunch, 250, per100),
    ]);
    expect(day.total.kcal, closeTo(700, 0.01));
    expect(day.total.protein, closeTo(35, 0.01));
    expect(day.totalOf(Meal.lunch).kcal, closeTo(500, 0.01));
    final back = DayLog.fromJson(day.date, day.toJson());
    expect(back.entries.length, 2);
    expect(back.entries.last.time, DateTime(2026, 11, 13, 12, 15));
    expect(back.entries.last.per100.kcal, closeTo(200, 0.5));
    expect(Meal.forTime(DateTime(2026, 1, 1, 7)), Meal.breakfast);
    expect(Meal.forTime(DateTime(2026, 1, 1, 13)), Meal.lunch);
    expect(Meal.forTime(DateTime(2026, 1, 1, 20)), Meal.dinner);
  });

  test('sugestão de metas (Mifflin-St Jeor)', () {
    final p = Profile(
      sex: 'M',
      birthYear: DateTime.now().year - 30,
      heightCm: 180,
      weightKg: 80,
      activity: Activity.sedentary,
      objective: Objective.keep,
    );
    // 10*80 + 6,25*180 - 5*30 + 5 = 1780; x 1,2 = 2136 -> 2140
    final g = p.suggestGoals();
    expect(g.kcal, 2140);
    expect(g.protein, 128);
    expect(g.waterMl, 2800);
    expect(const Profile().suggestGoals().kcal, 2000);
  });

  test('conversão de valores do Firestore ida e volta', () {
    final data = {
      'name': 'Ana',
      'n': 3,
      'kg': 61.5,
      'ok': true,
      'none': null,
      'list': [
        {'a': 1},
        'x'
      ],
      'empty': <Object>[],
      'map': {'kcal': 2000.0, 'by': ''},
    };
    expect(fromFields(toFields(data)), data);
    expect(toValue(5), {'integerValue': '5'});
    expect(fromValue({'arrayValue': <String, dynamic>{}}), isEmpty);
  });

  testWidgets('abre na tela de entrada e segue para o cadastro sem conta', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NutriVittaApp());
    final local = find.text('Usar sem conta neste aparelho');
    await _pumpUntil(tester, local);
    expect(local, findsOneWidget);
    await tester.tap(local);
    await tester.pumpAndSettle();
    expect(find.text('Sou paciente'), findsOneWidget);
    expect(find.text('Sou nutricionista'), findsOneWidget);
    await tester.tap(find.text('Sou paciente'));
    await tester.pumpAndSettle();
    expect(find.text('Sobre você'), findsOneWidget);

    final state = AppScope.read(tester.element(find.text('Sobre você')));
    state.finishOnboarding(
      const Profile(name: 'Ana', sex: 'F', birthYear: 1995, heightCm: 165, weightKg: 62),
      const Goals(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diário'), findsOneWidget);
    expect(find.text('Café da manhã'), findsOneWidget);

    const per100 = Nutrients(kcal: 124, protein: 2.6, carbs: 25.8, fat: 1);
    state.addEntry(_entry('x1', DateTime.now(), Meal.lunch, 200, per100));
    await tester.pumpAndSettle();
    expect(find.text('248 kcal'), findsWidgets);
    expect(state.dirty, contains(AppState.dirtyDay(dateKey(DateTime.now()))));
  });
}
