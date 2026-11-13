import 'package:flutter/material.dart';

import '../models/diary.dart';
import '../models/patient.dart';
import '../theme/nv_theme.dart';
import '../util/format.dart';
import 'common.dart';

/// Últimas pesagens e variação.
class WeightCard extends StatelessWidget {
  const WeightCard({super.key, required this.weights, this.onAdd});

  final List<WeightRecord> weights;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final recent = weights.reversed.take(5).toList();
    String? change;
    if (weights.length >= 2) {
      final diff = weights.last.kg - weights.first.kg;
      final sign = diff > 0 ? '+' : (diff < 0 ? '−' : '');
      change = '$sign${fmt(diff.abs(), 1)} kg desde ${shortDate(parseDateKey(weights.first.date))}';
    }
    return NvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Peso', style: text.titleMedium)),
              if (onAdd != null) TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Registrar')),
            ],
          ),
          if (weights.isEmpty)
            Text('Nenhuma pesagem registrada.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          else ...[
            Text('${fmt(weights.last.kg, 1)} kg', style: text.headlineMedium),
            if (change != null) Text(change, style: text.bodySmall),
            const SizedBox(height: 8),
            for (final w in recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(friendlyDate(parseDateKey(w.date)))),
                    Text('${fmt(w.kg, 1)} kg', style: text.labelLarge),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Dados básicos do paciente (sexo, idade, altura, peso, atividade e objetivo).
class ProfileSummary extends StatelessWidget {
  const ProfileSummary({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = profile;
    final bmi = p.heightCm > 0 && p.weightKg > 0 ? p.weightKg / ((p.heightCm / 100) * (p.heightCm / 100)) : null;
    return NvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dados do paciente', style: text.titleMedium),
          const SizedBox(height: 8),
          if (!p.hasMeasures)
            const Text('O paciente ainda não informou idade, altura e peso.')
          else ...[
            Text('${p.sex == 'M' ? 'Masculino' : 'Feminino'} · ${p.age} anos · ${fmt(p.heightCm)} cm · ${fmt(p.weightKg, 1)} kg'),
            if (bmi != null) Text('IMC ${fmt(bmi, 1)} (${bmiLabel(bmi)})'),
            Text('Atividade: ${p.activity.label} · Objetivo: ${p.objective.label}'),
          ],
        ],
      ),
    );
  }
}

String bmiLabel(double bmi) {
  if (bmi < 18.5) return 'abaixo do peso';
  if (bmi < 25) return 'peso adequado';
  if (bmi < 30) return 'sobrepeso';
  if (bmi < 35) return 'obesidade grau I';
  if (bmi < 40) return 'obesidade grau II';
  return 'obesidade grau III';
}

/// Tabela das medidas corporais: últimas avaliações lado a lado e a variação.
class MeasuresView extends StatelessWidget {
  const MeasuresView({super.key, required this.measures, this.onAdd, this.onTap});

  /// Ordenadas da mais antiga para a mais nova.
  final List<BodyMeasure> measures;
  final VoidCallback? onAdd;
  final ValueChanged<BodyMeasure>? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final last = measures.reversed.take(3).toList().reversed.toList();
    final first = measures.isEmpty ? null : measures.first;
    final now = measures.isEmpty ? null : measures.last;
    return NvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Medidas corporais', style: text.titleMedium)),
              if (onAdd != null) TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Nova avaliação')),
            ],
          ),
          if (measures.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Nenhuma avaliação registrada.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            )
          else ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                horizontalMargin: 0,
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                columns: [
                  const DataColumn(label: Text('')),
                  for (final m in last)
                    DataColumn(
                      numeric: true,
                      label: InkWell(
                        onTap: onTap == null ? null : () => onTap!(m),
                        child: Text(shortDate(parseDateKey(m.date)),
                            style: text.labelMedium?.copyWith(
                                color: onTap == null ? null : scheme.primary,
                                decoration: onTap == null ? null : TextDecoration.underline)),
                      ),
                    ),
                  if (measures.length > 1) const DataColumn(numeric: true, label: Text('Variação')),
                ],
                rows: [
                  for (final k in MeasureKind.all)
                    if (measures.any((m) => m[k.key] != null))
                      DataRow(cells: [
                        DataCell(Text(k.label)),
                        for (final m in last) DataCell(Text(m[k.key] == null ? '-' : '${fmt(m[k.key]!, 1)} ${k.unit}')),
                        if (measures.length > 1) DataCell(_Delta(first?[k.key], now?[k.key], k.unit)),
                      ]),
                  if (now?.waistHip != null)
                    DataRow(cells: [
                      const DataCell(Text('Cintura/quadril')),
                      for (final m in last) DataCell(Text(m.waistHip == null ? '-' : fmt(m.waistHip!, 2))),
                      if (measures.length > 1) const DataCell(Text('')),
                    ]),
                ],
              ),
            ),
            if (measures.length > 1)
              Text('Variação entre ${shortDate(parseDateKey(first!.date))} e ${shortDate(parseDateKey(now!.date))}.',
                  style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta(this.from, this.to, this.unit);

  final double? from;
  final double? to;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (from == null || to == null) return const Text('-');
    final d = to! - from!;
    final sign = d > 0 ? '+' : (d < 0 ? '−' : '');
    return Text('$sign${fmt(d.abs(), 1)} $unit',
        style: TextStyle(color: d == 0 ? null : (d < 0 ? NvColors.green : NvColors.orange), fontWeight: FontWeight.w600));
  }
}

/// Anamnese só para leitura, por seção.
class AnamnesisView extends StatelessWidget {
  const AnamnesisView({super.key, required this.anamnesis, this.onEdit});

  final Anamnesis anamnesis;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final a = anamnesis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NvCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Anamnese', style: text.titleMedium),
                    Text(
                      a.isEmpty
                          ? 'Ainda não preenchida.'
                          : '${a.filled} de ${Anamnesis.total} respostas'
                              '${_updated(a.updatedAt)}'
                              '${a.updatedBy.isEmpty ? '' : ' por ${a.updatedBy}'}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                FilledButton.tonalIcon(
                    onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: Text(a.isEmpty ? 'Preencher' : 'Editar')),
            ],
          ),
        ),
        for (final (title, fields) in Anamnesis.sections)
          if (fields.any((f) => a[f.key].trim().isNotEmpty)) ...[
            const SizedBox(height: 12),
            NvCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  for (final f in fields)
                    if (a[f.key].trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(f.label, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(a[f.key]),
                    ],
                ],
              ),
            ),
          ],
      ],
    );
  }
}

String _updated(String iso) {
  final t = DateTime.tryParse(iso);
  return t == null ? '' : ' · atualizada em ${shortDate(t.toLocal())}';
}

/// Edição da anamnese. Devolve as respostas ao salvar.
class AnamnesisEditScreen extends StatefulWidget {
  const AnamnesisEditScreen({super.key, required this.anamnesis, this.title = 'Anamnese', this.intro});

  final Anamnesis anamnesis;
  final String title;
  final String? intro;

  @override
  State<AnamnesisEditScreen> createState() => _AnamnesisEditScreenState();
}

class _AnamnesisEditScreenState extends State<AnamnesisEditScreen> {
  late final Map<String, TextEditingController> _ctrl = {
    for (final (_, fields) in Anamnesis.sections)
      for (final f in fields) f.key: TextEditingController(text: widget.anamnesis[f.key]),
  };

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    Navigator.pop(context, Anamnesis({for (final e in _ctrl.entries) e.key: e.value.text.trim()}));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [TextButton(onPressed: _save, child: const Text('Salvar'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (widget.intro != null) Text(widget.intro!, style: text.bodyMedium),
          for (final (title, fields) in Anamnesis.sections) ...[
            SectionTitle(title),
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _ctrl[f.key],
                  minLines: 1,
                  maxLines: f.lines + 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: f.label, hintText: f.hint.isEmpty ? null : f.hint),
                ),
              ),
          ],
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Salvar anamnese')),
        ],
      ),
    );
  }
}

/// Nova avaliação de medidas (ou edição de uma existente). Devolve a avaliação.
class MeasureEditScreen extends StatefulWidget {
  const MeasureEditScreen({super.key, this.initial, this.by = ''});

  final BodyMeasure? initial;
  final String by;

  @override
  State<MeasureEditScreen> createState() => _MeasureEditScreenState();
}

class _MeasureEditScreenState extends State<MeasureEditScreen> {
  late DateTime _date = widget.initial == null ? dayOnly(DateTime.now()) : parseDateKey(widget.initial!.date);
  late final Map<String, TextEditingController> _ctrl = {
    for (final k in MeasureKind.all)
      k.key: TextEditingController(text: widget.initial?[k.key] == null ? '' : fmt(widget.initial![k.key]!, 1)),
  };

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(now.year - 5), lastDate: dayOnly(now));
    if (d != null) setState(() => _date = dayOnly(d));
  }

  void _save() {
    final values = <String, double>{};
    for (final k in MeasureKind.all) {
      final v = parseNumber(_ctrl[k.key]!.text);
      if (v == null || v <= 0) continue;
      if (k.unit == '%' ? v > 80 : v > 300) {
        showSnack(context, 'Confira o valor de ${k.label.toLowerCase()}.');
        return;
      }
      values[k.key] = v;
    }
    if (values.isEmpty) {
      showSnack(context, 'Preencha pelo menos uma medida.');
      return;
    }
    Navigator.pop(context, BodyMeasure(dateKey(_date), values, by: widget.by));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Nova avaliação' : 'Editar avaliação')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: widget.initial == null ? _pickDate : null,
            icon: const Icon(Icons.event_outlined),
            label: Text(friendlyDate(_date)),
          ),
          const SizedBox(height: 8),
          Text('Medidas com fita métrica, em centímetros. Deixe em branco o que não foi medido.', style: text.bodySmall),
          const SizedBox(height: 12),
          for (var i = 0; i < MeasureKind.all.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (final k in MeasureKind.all.skip(i).take(2)) ...[
                    Expanded(child: NumberField(controller: _ctrl[k.key]!, label: k.label, suffix: k.unit)),
                    if (k != MeasureKind.all.skip(i).take(2).last) const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Salvar avaliação')),
        ],
      ),
    );
  }
}
