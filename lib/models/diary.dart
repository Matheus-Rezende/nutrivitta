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
      };

  static FoodEntry fromJson(Map<String, dynamic> j) => FoodEntry(
        id: (j['id'] as String?) ?? '',
        time: DateTime.tryParse((j['time'] as String?) ?? '') ?? DateTime.now(),
        meal: Meal.parse(j['meal'] as String?),
        foodId: (j['foodId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        grams: _d(j['grams']),
        nutrients: Nutrients.fromJson(j),
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

enum Role { patient, nutritionist }

enum Activity {
  sedentary('Sedentário', 'Pouco ou nenhum exercício', 1.2),
  light('Leve', 'Exercício 1 a 3 dias na semana', 1.375),
  moderate('Moderado', 'Exercício 3 a 5 dias na semana', 1.55),
  intense('Intenso', 'Exercício 6 a 7 dias na semana', 1.725);

  const Activity(this.label, this.hint, this.factor);

  final String label;
  final String hint;
  final double factor;
}

enum Objective {
  lose('Emagrecer', -500),
  keep('Manter o peso', 0),
  gain('Ganhar massa', 300);

  const Objective(this.label, this.kcalDelta);

  final String label;
  final double kcalDelta;
}

/// Dados da conta: papel (paciente ou nutricionista) e medidas.
class Profile {
  const Profile({
    this.role = Role.patient,
    this.name = '',
    this.email = '',
    this.crn = '',
    this.inviteCode = '',
    this.sex = 'F',
    this.birthYear = 0,
    this.heightCm = 0,
    this.weightKg = 0,
    this.activity = Activity.light,
    this.objective = Objective.keep,
    this.nutritionistUid = '',
    this.nutritionistName = '',
  });

  final Role role;
  final String name;
  final String email;

  // nutricionista
  final String crn;
  final String inviteCode;

  // paciente
  final String sex; // 'F' ou 'M'
  final int birthYear;
  final double heightCm;
  final double weightKg;
  final Activity activity;
  final Objective objective;
  final String nutritionistUid;
  final String nutritionistName;

  bool get isNutritionist => role == Role.nutritionist;
  bool get hasNutritionist => nutritionistUid.isNotEmpty;
  bool get hasMeasures => birthYear > 0 && heightCm > 0 && weightKg > 0;

  Profile copyWith({
    Role? role,
    String? name,
    String? email,
    String? crn,
    String? inviteCode,
    String? sex,
    int? birthYear,
    double? heightCm,
    double? weightKg,
    Activity? activity,
    Objective? objective,
    String? nutritionistUid,
    String? nutritionistName,
  }) =>
      Profile(
        role: role ?? this.role,
        name: name ?? this.name,
        email: email ?? this.email,
        crn: crn ?? this.crn,
        inviteCode: inviteCode ?? this.inviteCode,
        sex: sex ?? this.sex,
        birthYear: birthYear ?? this.birthYear,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        activity: activity ?? this.activity,
        objective: objective ?? this.objective,
        nutritionistUid: nutritionistUid ?? this.nutritionistUid,
        nutritionistName: nutritionistName ?? this.nutritionistName,
      );

  /// Campos gravados no documento do usuário (as metas vão à parte).
  static const fields = [
    'role', 'name', 'email', 'crn', 'inviteCode', 'sex', 'birthYear', 'heightCm', 'weightKg',
    'activity', 'objective', 'nutritionistUid', 'nutritionistName', 'updatedAt',
  ];

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'name': name,
        'email': email,
        'crn': crn,
        'inviteCode': inviteCode,
        'sex': sex,
        'birthYear': birthYear,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activity': activity.name,
        'objective': objective.name,
        'nutritionistUid': nutritionistUid,
        'nutritionistName': nutritionistName,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        role: j['role'] == Role.nutritionist.name ? Role.nutritionist : Role.patient,
        name: (j['name'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        crn: (j['crn'] as String?) ?? '',
        inviteCode: (j['inviteCode'] as String?) ?? '',
        sex: j['sex'] == 'M' ? 'M' : 'F',
        birthYear: _i(j['birthYear']),
        heightCm: _d(j['heightCm']),
        weightKg: _d(j['weightKg']),
        activity: Activity.values.firstWhere((a) => a.name == j['activity'], orElse: () => Activity.light),
        objective: Objective.values.firstWhere((o) => o.name == j['objective'], orElse: () => Objective.keep),
        nutritionistUid: (j['nutritionistUid'] as String?) ?? '',
        nutritionistName: (j['nutritionistName'] as String?) ?? '',
      );

  /// Estimativa de metas pela equação de Mifflin-St Jeor. É só um ponto de
  /// partida: o nutricionista ajusta para cada pessoa.
  Goals suggestGoals() {
    if (!hasMeasures) return const Goals();
    final age = (DateTime.now().year - birthYear).clamp(10, 100);
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (sex == 'M' ? 5 : -161);
    var kcal = bmr * activity.factor + objective.kcalDelta;
    if (kcal < 1200) kcal = 1200;
    kcal = (kcal / 10).roundToDouble() * 10;
    final protein = (weightKg * (objective == Objective.keep ? 1.6 : 1.8)).roundToDouble();
    final fat = (kcal * 0.27 / 9).roundToDouble();
    var carbs = ((kcal - protein * 4 - fat * 9) / 4).roundToDouble();
    if (carbs < 50) carbs = 50;
    final water = ((weightKg * 35) / 50).round() * 50;
    return Goals(kcal: kcal, protein: protein, carbs: carbs, fat: fat, waterMl: water);
  }
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
  const DayComment(this.date, this.text, this.author);

  final String date;
  final String text;
  final String author;

  Map<String, dynamic> toJson() => {'text': text, 'author': author};

  static DayComment fromJson(String date, Map<String, dynamic> j) =>
      DayComment(date, (j['text'] as String?) ?? '', (j['author'] as String?) ?? '');
}

/// Lista de dias (chaves) terminando em [end], do mais antigo ao mais novo.
List<String> lastDays(DateTime end, int count) =>
    [for (var i = count - 1; i >= 0; i--) dateKey(DateTime(end.year, end.month, end.day - i))];
