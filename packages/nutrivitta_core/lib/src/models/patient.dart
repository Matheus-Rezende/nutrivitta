import '../util/format.dart';
import 'diary.dart';

double _d(Object? v) => v is num ? v.toDouble() : 0;
int _i(Object? v) => v is num ? v.round() : 0;
String _s(Object? v) => v is String ? v : '';

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

/// Perfil do paciente (documento users/{uid}).
class Profile {
  const Profile({
    this.name = '',
    this.email = '',
    this.sex = 'F',
    this.birthYear = 0,
    this.heightCm = 0,
    this.weightKg = 0,
    this.activity = Activity.light,
    this.objective = Objective.keep,
    this.nutritionistUids = const [],
  });

  final String name;
  final String email;
  final String sex; // 'F' ou 'M'
  final int birthYear;
  final double heightCm;
  final double weightKg;
  final Activity activity;
  final Objective objective;

  /// Nutricionistas autorizados pelo paciente a ver os dados. Só o próprio
  /// paciente altera esta lista; as regras do banco se baseiam nela.
  final List<String> nutritionistUids;

  bool get hasMeasures => birthYear > 0 && heightCm > 0 && weightKg > 0;

  int get age => birthYear <= 0 ? 0 : DateTime.now().year - birthYear;

  Profile copyWith({
    String? name,
    String? email,
    String? sex,
    int? birthYear,
    double? heightCm,
    double? weightKg,
    Activity? activity,
    Objective? objective,
    List<String>? nutritionistUids,
  }) =>
      Profile(
        name: name ?? this.name,
        email: email ?? this.email,
        sex: sex ?? this.sex,
        birthYear: birthYear ?? this.birthYear,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        activity: activity ?? this.activity,
        objective: objective ?? this.objective,
        nutritionistUids: nutritionistUids ?? this.nutritionistUids,
      );

  /// Campos gravados no documento do paciente (as metas vão à parte).
  static const fields = [
    'name', 'email', 'sex', 'birthYear', 'heightCm', 'weightKg', 'activity', 'objective',
    'nutritionistUids', 'updatedAt',
  ];

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'sex': sex,
        'birthYear': birthYear,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activity': activity.name,
        'objective': objective.name,
        'nutritionistUids': nutritionistUids,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        name: _s(j['name']),
        email: _s(j['email']),
        sex: j['sex'] == 'M' ? 'M' : 'F',
        birthYear: _i(j['birthYear']),
        heightCm: _d(j['heightCm']),
        weightKg: _d(j['weightKg']),
        activity: Activity.values.firstWhere((a) => a.name == j['activity'], orElse: () => Activity.light),
        objective: Objective.values.firstWhere((o) => o.name == j['objective'], orElse: () => Objective.keep),
        nutritionistUids: [for (final u in (j['nutritionistUids'] as List? ?? const [])) '$u'],
      );

  /// Estimativa de metas pela equação de Mifflin-St Jeor. É só um ponto de
  /// partida: o nutricionista ajusta para cada pessoa.
  Goals suggestGoals() {
    if (!hasMeasures) return const Goals();
    final age = this.age.clamp(10, 100);
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

/// Uma pergunta da anamnese.
class AnamnesisField {
  const AnamnesisField(this.key, this.label, {this.hint = '', this.lines = 2});

  final String key;
  final String label;
  final String hint;
  final int lines;
}

/// Anamnese nutricional: perguntas abertas, preenchidas pelo paciente ou pelo
/// nutricionista (documento users/{uid}/meta/anamnesis).
class Anamnesis {
  const Anamnesis([this.answers = const {}, this.updatedAt = '', this.updatedBy = '']);

  final Map<String, String> answers;
  final String updatedAt;
  final String updatedBy;

  static const sections = <(String, List<AnamnesisField>)>[
    (
      'Objetivo e rotina',
      [
        AnamnesisField('goal', 'Objetivo com o acompanhamento', hint: 'Ex.: emagrecer 6 kg, melhorar a disposição'),
        AnamnesisField('routine', 'Rotina e horários', hint: 'Trabalho, estudo, horários em que costuma comer', lines: 3),
        AnamnesisField('activity', 'Atividade física', hint: 'Qual, quantas vezes por semana e duração'),
        AnamnesisField('sleep', 'Sono', hint: 'Horas por noite e qualidade'),
        AnamnesisField('water', 'Consumo de água', hint: 'Copos ou litros por dia'),
      ],
    ),
    (
      'Alimentação',
      [
        AnamnesisField('likes', 'Alimentos de que gosta'),
        AnamnesisField('dislikes', 'Alimentos de que não gosta'),
        AnamnesisField('restrictions', 'Restrições ou escolhas alimentares', hint: 'Ex.: vegetariano, sem lactose'),
        AnamnesisField('allergies', 'Alergias e intolerâncias'),
        AnamnesisField('appetite', 'Apetite, fome e vontade de doces'),
        AnamnesisField('bowel', 'Funcionamento do intestino'),
        AnamnesisField('alcohol', 'Bebida alcoólica e cigarro', hint: 'Frequência e quantidade'),
      ],
    ),
    (
      'Saúde',
      [
        AnamnesisField('conditions', 'Doenças ou condições de saúde'),
        AnamnesisField('medications', 'Medicamentos e suplementos em uso'),
        AnamnesisField('family', 'Histórico familiar', hint: 'Ex.: diabetes, pressão alta, colesterol'),
        AnamnesisField('exams', 'Exames recentes alterados'),
        AnamnesisField('notes', 'Outras observações', lines: 3),
      ],
    ),
  ];

  String operator [](String key) => answers[key] ?? '';

  bool get isEmpty => answers.values.every((v) => v.trim().isEmpty);

  int get filled => answers.values.where((v) => v.trim().isNotEmpty).length;

  static int get total => sections.fold(0, (a, s) => a + s.$2.length);

  Map<String, dynamic> toJson() => {
        'answers': {for (final e in answers.entries) if (e.value.trim().isNotEmpty) e.key: e.value.trim()},
        'updatedAt': updatedAt,
        'updatedBy': updatedBy,
      };

  static Anamnesis fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Anamnesis();
    final a = j['answers'];
    return Anamnesis(
      a is Map ? {for (final e in a.entries) '${e.key}': '${e.value}'} : const {},
      _s(j['updatedAt']),
      _s(j['updatedBy']),
    );
  }
}

/// Uma medida corporal (circunferências em cm, gordura em %).
class MeasureKind {
  const MeasureKind(this.key, this.label, this.unit);

  final String key;
  final String label;
  final String unit;

  static const all = [
    MeasureKind('waist', 'Cintura', 'cm'),
    MeasureKind('abdomen', 'Abdômen', 'cm'),
    MeasureKind('hip', 'Quadril', 'cm'),
    MeasureKind('chest', 'Tórax', 'cm'),
    MeasureKind('arm', 'Braço', 'cm'),
    MeasureKind('thigh', 'Coxa', 'cm'),
    MeasureKind('calf', 'Panturrilha', 'cm'),
    MeasureKind('fat', 'Gordura corporal', '%'),
  ];
}

/// Avaliação das medidas corporais em uma data.
class BodyMeasure {
  const BodyMeasure(this.date, this.values, {this.by = ''});

  /// aaaa-mm-dd
  final String date;
  final Map<String, double> values;

  /// Quem registrou (nome do nutricionista; vazio: o próprio paciente).
  final String by;

  double? operator [](String key) => values[key];

  /// Relação cintura/quadril, quando as duas medidas existem.
  double? get waistHip {
    final w = values['waist'];
    final h = values['hip'];
    if (w == null || h == null || h == 0) return null;
    return w / h;
  }

  Map<String, dynamic> toJson() => {'date': date, 'values': values, if (by.isNotEmpty) 'by': by};

  static BodyMeasure fromJson(Map<String, dynamic> j) {
    final v = j['values'];
    return BodyMeasure(
      _s(j['date']),
      v is Map ? {for (final e in v.entries) if (e.value is num) '${e.key}': (e.value as num).toDouble()} : const {},
      by: _s(j['by']),
    );
  }

  /// Lista ordenada (mais antiga primeiro), um registro por dia.
  static List<BodyMeasure> upsert(List<BodyMeasure> list, BodyMeasure m) =>
      [...list.where((x) => x.date != m.date), m]..sort((a, b) => a.date.compareTo(b.date));

  String get label => friendlyDate(parseDateKey(date));
}
