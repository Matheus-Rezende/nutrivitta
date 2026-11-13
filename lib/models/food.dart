import 'dart:convert';

import '../util/format.dart';

/// Valores nutricionais de uma quantidade de alimento.
class Nutrients {
  const Nutrients({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0, this.fiber = 0});

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;

  static const zero = Nutrients();

  Nutrients operator +(Nutrients o) => Nutrients(
        kcal: kcal + o.kcal,
        protein: protein + o.protein,
        carbs: carbs + o.carbs,
        fat: fat + o.fat,
        fiber: fiber + o.fiber,
      );

  Nutrients scale(double f) =>
      Nutrients(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f, fiber: fiber * f);

  Map<String, dynamic> toJson() => {'kcal': _r(kcal), 'protein': _r(protein), 'carbs': _r(carbs), 'fat': _r(fat), 'fiber': _r(fiber)};

  static Nutrients fromJson(Map<String, dynamic> j) => Nutrients(
        kcal: _d(j['kcal']),
        protein: _d(j['protein']),
        carbs: _d(j['carbs']),
        fat: _d(j['fat']),
        fiber: _d(j['fiber']),
      );
}

double _r(double v) => (v * 10).roundToDouble() / 10;
double _d(Object? v) => v is num ? v.toDouble() : 0;

/// Um alimento, com os valores por 100 g.
class Food {
  Food({
    required this.id,
    required this.name,
    required this.per100,
    this.category = '',
    this.custom = false,
    this.portionName = '',
    this.portionGrams = 0,
  }) : _search = normalize(name);

  /// "taco:12" para a tabela embutida, "meu:..." para os cadastrados.
  final String id;
  final String name;
  final Nutrients per100;
  final String category;
  final bool custom;

  /// Medida caseira opcional (ex.: "1 fatia" = 30 g).
  final String portionName;
  final double portionGrams;

  final String _search;

  bool get hasPortion => portionName.isNotEmpty && portionGrams > 0;

  Nutrients forGrams(double grams) => per100.scale(grams / 100);

  bool matches(List<String> tokens) => tokens.every(_search.contains);

  bool startsWith(String token) => _search.startsWith(token);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        ...per100.toJson(),
        if (hasPortion) 'portionName': portionName,
        if (hasPortion) 'portionGrams': portionGrams,
      };

  static Food fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        per100: Nutrients.fromJson(j),
        category: 'Meus alimentos',
        custom: true,
        portionName: (j['portionName'] as String?) ?? '',
        portionGrams: _d(j['portionGrams']),
      );
}

/// Tabela de alimentos embutida no app (TACO), funciona sem internet.
class FoodDb {
  FoodDb(this.foods, this.source);

  final List<Food> foods;
  final String source;

  static FoodDb parse(String jsonText) {
    final j = jsonDecode(jsonText) as Map<String, dynamic>;
    final cats = (j['categories'] as List).cast<String>();
    final foods = <Food>[
      for (final row in (j['foods'] as List).cast<List>())
        Food(
          id: 'taco:${row[0]}',
          category: cats[row[1] as int],
          name: row[2] as String,
          per100: Nutrients(
            kcal: _d(row[3]),
            protein: _d(row[4]),
            carbs: _d(row[5]),
            fat: _d(row[6]),
            fiber: _d(row[7]),
          ),
        ),
    ];
    return FoodDb(foods, (j['source'] as String?) ?? '');
  }

  /// Busca por todas as palavras digitadas; quem começa com a primeira vem antes.
  List<Food> search(String query, {List<Food> extra = const [], int limit = 60}) {
    final tokens = normalize(query).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];
    final first = <Food>[];
    final rest = <Food>[];
    for (final f in [...extra, ...foods]) {
      if (!f.matches(tokens)) continue;
      (f.startsWith(tokens.first) ? first : rest).add(f);
    }
    final all = [...first, ...rest];
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  Food? byId(String id, {List<Food> extra = const []}) {
    for (final f in extra) {
      if (f.id == id) return f;
    }
    for (final f in foods) {
      if (f.id == id) return f;
    }
    return null;
  }
}
