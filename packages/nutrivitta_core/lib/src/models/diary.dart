import 'package:flutter/material.dart';

import '../util/format.dart';
import 'food.dart';

double _d(Object? v) => v is num ? v.toDouble() : 0;
int _i(Object? v) => v is num ? v.round() : 0;

/// Refeições do dia.
enum Meal {
  breakfast('Café da manhã', Icons.free_breakfast_outlined),
  morningSnack('Lanche da manhã', Icons.apple),
  lunch('Almoço', Icons.restaurant_outlined),
  afternoonSnack('Lanche da tarde', Icons.cookie_outlined),
  dinner('Jantar', Icons.dinner_dining_outlined),
  supper('Ceia', Icons.nightlight_outlined);

  const Meal(this.label, this.icon);

  final String label;
  final IconData icon;

  static Meal parse(String? name) => Meal.values.firstWhere((m) => m.name == name, orElse: () => Meal.lunch);

  /// Refeição mais provável para o horário.
  static Meal forTime(DateTime t) {
    final m = t.hour * 60 + t.minute;
    if (m < 4 * 60) return Meal.supper;
    if (m < 9 * 60 + 30) return Meal.breakfast;
    if (m < 11 * 60 + 30) return Meal.morningSnack;
    if (m < 14 * 60 + 30) return Meal.lunch;
    if (m < 18 * 60) return Meal.afternoonSnack;
    if (m < 21 * 60 + 30) return Meal.dinner;
    return Meal.supper;
  }
}

/// Um alimento consumido: o que foi, quanto e quando.
class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.time,
    required this.meal,
    required this.foodId,
    required this.name,
    required this.grams,
    required this.nutrients,
    this.hasPhoto = false,
  });

  final String id;

  /// Data e hora em que a pessoa comeu (horário local).
  final DateTime time;
  final Meal meal;
  final String foodId;
  final String name;
  final double grams;

  /// Valores já calculados para a quantidade consumida.
  final Nutrients nutrients;

  /// Tem foto da refeição (guardada à parte, em users/{uid}/photos/{id}).
  final bool hasPhoto;

  FoodEntry copyWith({DateTime? time, Meal? meal, double? grams, Nutrients? nutrients, bool? hasPhoto}) => FoodEntry(
        id: id,
        time: time ?? this.time,
        meal: meal ?? this.meal,
        foodId: foodId,
        name: name,
        grams: grams ?? this.grams,
        nutrients: nutrients ?? this.nutrients,
        hasPhoto: hasPhoto ?? this.hasPhoto,
      );

  /// Valores por 100 g, recuperados do que foi gravado (para editar a quantidade).
  Nutrients get per100 => grams > 0 ? nutrients.scale(100 / grams) : Nutrients.zero;

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'meal': meal.name,
        'foodId': foodId,
        'name': name,
        'grams': grams,
        ...nutrients.toJson(),
        if (hasPhoto) 'photo': true,
      };

  static FoodEntry fromJson(Map<String, dynamic> j) => FoodEntry(
        id: (j['id'] as String?) ?? '',
        time: DateTime.tryParse((j['time'] as String?) ?? '') ?? DateTime.now(),
        meal: Meal.parse(j['meal'] as String?),
        foodId: (j['foodId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        grams: _d(j['grams']),
        nutrients: Nutrients.fromJson(j),
        hasPhoto: j['photo'] == true,
      );
}

/// Tudo o que foi registrado em um dia.
class DayLog {
  DayLog(this.date, {List<FoodEntry>? entries, this.waterMl = 0, this.updatedAt}) : entries = entries ?? [];

  /// aaaa-mm-dd
  final String date;
  final List<FoodEntry> entries;
  int waterMl;
  DateTime? updatedAt;

  bool get isEmpty => entries.isEmpty && waterMl == 0;

  Nutrients get total => entries.fold(Nutrients.zero, (a, e) => a + e.nutrients);

  List<FoodEntry> of(Meal meal) => entries.where((e) => e.meal == meal).toList()..sort((a, b) => a.time.compareTo(b.time));

  Nutrients totalOf(Meal meal) => entries.where((e) => e.meal == meal).fold(Nutrients.zero, (a, e) => a + e.nutrients);

  Map<String, dynamic> toJson() => {
        'date': date,
        'entries': [for (final e in entries) e.toJson()],
        'waterMl': waterMl,
        'kcal': total.kcal.roundToDouble(),
        'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      };

  static DayLog fromJson(String date, Map<String, dynamic> j) => DayLog(
        date,
        entries: [
          for (final e in (j['entries'] as List? ?? const [])) FoodEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
        waterMl: _i(j['waterMl']),
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
      );
}

/// Metas diárias.
class Goals {
  const Goals({
    this.kcal = 2000,
    this.protein = 100,
    this.carbs = 250,
    this.fat = 65,
    this.waterMl = 2000,
    this.updatedAt,
    this.by = '',
  });

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final int waterMl;
  final DateTime? updatedAt;

  /// Nome do nutricionista que definiu as metas (vazio: a própria pessoa).
  final String by;

  Goals stamped({String by = ''}) => Goals(
      kcal: kcal, protein: protein, carbs: carbs, fat: fat, waterMl: waterMl, updatedAt: DateTime.now().toUtc(), by: by);

  Map<String, dynamic> toJson() => {
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'waterMl': waterMl,
        'updatedAt': (updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).toIso8601String(),
        'by': by,
      };

  static Goals fromJson(Map<String, dynamic> j) => Goals(
        kcal: j['kcal'] is num ? _d(j['kcal']) : 2000,
        protein: j['protein'] is num ? _d(j['protein']) : 100,
        carbs: j['carbs'] is num ? _d(j['carbs']) : 250,
        fat: j['fat'] is num ? _d(j['fat']) : 65,
        waterMl: j['waterMl'] is num ? _i(j['waterMl']) : 2000,
        updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? ''),
        by: (j['by'] as String?) ?? '',
      );
}

/// Pesagem registrada.
class WeightRecord {
  const WeightRecord(this.date, this.kg);

  final String date;
  final double kg;

  Map<String, dynamic> toJson() => {'date': date, 'kg': kg};

  static WeightRecord fromJson(Map<String, dynamic> j) => WeightRecord((j['date'] as String?) ?? '', _d(j['kg']));
}

/// Recado do nutricionista sobre um dia.
class DayComment {
  const DayComment(this.date, this.text, this.author, {this.updatedAt = ''});

  final String date;
  final String text;
  final String author;

  /// Momento da última edição (ISO 8601), usado para avisar recados novos.
  final String updatedAt;

  Map<String, dynamic> toJson() => {
        'text': text,
        'author': author,
        'updatedAt': updatedAt.isEmpty ? DateTime.now().toUtc().toIso8601String() : updatedAt,
      };

  static DayComment fromJson(String date, Map<String, dynamic> j) => DayComment(
      date, (j['text'] as String?) ?? '', (j['author'] as String?) ?? '',
      updatedAt: (j['updatedAt'] as String?) ?? '');
}

/// Lista de dias (chaves) terminando em [end], do mais antigo ao mais novo.
List<String> lastDays(DateTime end, int count) =>
    [for (var i = count - 1; i >= 0; i--) dateKey(DateTime(end.year, end.month, end.day - i))];
