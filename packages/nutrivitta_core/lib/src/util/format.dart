/// Datas e números no padrão brasileiro.
library;

String two(int v) => v.toString().padLeft(2, '0');

/// Chave do dia: aaaa-mm-dd.
String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

const _weekdays = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
const _weekdaysShort = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

/// "Hoje", "Ontem" ou "sexta, 13 nov".
String friendlyDate(DateTime d) {
  final today = dayOnly(DateTime.now());
  final day = dayOnly(d);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Ontem';
  if (diff == -1) return 'Amanhã';
  final base = '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
  return d.year == today.year ? base : '$base ${d.year}';
}

String shortDate(DateTime d) => '${two(d.day)}/${two(d.month)}';

String hourMinute(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

/// Número com vírgula decimal, sem zeros sobrando.
String fmt(num v, [int decimals = 0]) {
  var s = v.toStringAsFixed(decimals);
  if (decimals > 0 && s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s.replaceAll('.', ',');
}

String fmtG(num v) => '${fmt(v, v < 10 ? 1 : 0)} g';

double? parseNumber(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
  return v;
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Minúsculas e sem acentos, para a busca.
String normalize(String text) {
  final b = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}
