import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

FoodEntry _entry(String id, DateTime time, Meal meal, double grams, Nutrients per100) => FoodEntry(
    id: id, time: time, meal: meal, foodId: 'taco:1', name: 'Teste', grams: grams, nutrients: per100.scale(grams / 100));

void main() {
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

  test('totais do dia, refeições e foto', () {
    const per100 = Nutrients(kcal: 200, protein: 10, carbs: 20, fat: 5, fiber: 2);
    final day = DayLog('2026-11-13', entries: [
      _entry('a', DateTime(2026, 11, 13, 7, 30), Meal.breakfast, 100, per100),
      _entry('b', DateTime(2026, 11, 13, 12, 15), Meal.lunch, 250, per100).copyWith(hasPhoto: true),
    ]);
    expect(day.total.kcal, closeTo(700, 0.01));
    expect(day.total.protein, closeTo(35, 0.01));
    expect(day.totalOf(Meal.lunch).kcal, closeTo(500, 0.01));
    final back = DayLog.fromJson(day.date, day.toJson());
    expect(back.entries.length, 2);
    expect(back.entries.last.time, DateTime(2026, 11, 13, 12, 15));
    expect(back.entries.last.per100.kcal, closeTo(200, 0.5));
    expect(back.entries.last.hasPhoto, isTrue);
    expect(back.entries.first.hasPhoto, isFalse);
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

  test('perfil guarda os nutricionistas autorizados', () {
    const p = Profile(name: 'Ana', nutritionistUids: ['n1', 'n2']);
    final back = Profile.fromJson(p.toJson());
    expect(back.nutritionistUids, ['n1', 'n2']);
    expect(Profile.fields, contains('nutritionistUids'));
  });

  test('anamnese e medidas corporais', () {
    const a = Anamnesis({'goal': 'Emagrecer 5 kg', 'sleep': '  ', 'allergies': 'Camarão'});
    final back = Anamnesis.fromJson(a.toJson());
    expect(back['goal'], 'Emagrecer 5 kg');
    expect(back['sleep'], '');
    expect(back.filled, 2);
    expect(Anamnesis.total, greaterThan(10));
    expect(Anamnesis.fromJson(null).isEmpty, isTrue);

    var list = <BodyMeasure>[];
    list = BodyMeasure.upsert(list, const BodyMeasure('2026-11-10', {'waist': 90, 'hip': 100}));
    list = BodyMeasure.upsert(list, const BodyMeasure('2026-10-10', {'waist': 94}));
    list = BodyMeasure.upsert(list, const BodyMeasure('2026-11-10', {'waist': 89, 'hip': 100}));
    expect(list.map((m) => m.date), ['2026-10-10', '2026-11-10']);
    expect(list.last['waist'], 89);
    expect(list.last.waistHip, closeTo(0.89, 0.001));
    expect(BodyMeasure.fromJson(list.last.toJson())['hip'], 100);
  });

  test('pedido de conexão', () {
    const l = Link(proUid: 'p1', patientUid: 'u1', proName: 'Dra. Bia', patientEmail: 'ana@x.com');
    expect(l.id, 'p1_u1');
    expect(l.pending, isTrue);
    final back = Link.fromJson(l.withStatus(LinkStatus.accepted).toJson());
    expect(back.accepted, isTrue);
    expect(back.proName, 'Dra. Bia');
    expect(back.patientLabel, 'ana@x.com');
    expect(LinkStatus.parse('xyz'), LinkStatus.pending);
    expect(Remote.emailKey('  Ana@Gmail.COM '), 'ana@gmail.com');
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
}
