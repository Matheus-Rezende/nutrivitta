import 'package:flutter/material.dart';

import '../cloud/remote.dart';
import '../models/diary.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/day_view.dart';
import '../widgets/summary_view.dart';
import 'goals_screen.dart';
import 'summary_screen.dart';

/// Tela do nutricionista para um paciente: diário (só leitura), resumo,
/// metas e recados.
class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key, required this.patient});

  final PatientLink patient;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final _remote = Remote.instance;

  Profile? _profile;
  Goals _goals = const Goals();
  String? _error;

  // diário
  DateTime _date = dayOnly(DateTime.now());
  DayLog? _day;
  DayComment? _comment;
  bool _loadingDay = true;

  // resumo
  int _range = 7;
  Map<String, DayLog>? _rangeDays;
  List<WeightRecord> _weights = const [];

  String get _uid => widget.patient.uid;
  bool get _isToday => dateKey(_date) == dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (_error != null) setState(() => _error = null);
    try {
      final user = await _remote.user(_uid);
      if (user == null) throw StateError('Paciente sem dados');
      if (!mounted) return;
      setState(() {
        _profile = Profile.fromJson(user);
        final g = user['goals'];
        _goals = g is Map ? Goals.fromJson(Map<String, dynamic>.from(g)) : const Goals();
      });
      await Future.wait([_loadDay(), _loadRange()]);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir os dados deste paciente. '
            'Ele pode ter desfeito o vínculo, ou a conexão falhou.');
      }
    }
  }

  Future<void> _loadDay() async {
    final key = dateKey(_date);
    if (!_loadingDay) setState(() => _loadingDay = true);
    try {
      final results = await Future.wait<Object?>([_remote.day(_uid, key), _remote.comment(_uid, key)]);
      if (!mounted || key != dateKey(_date)) return;
      setState(() {
        _day = (results[0] as DayLog?) ?? DayLog(key);
        _comment = results[1] as DayComment?;
        _loadingDay = false;
      });
    } catch (e) {
      if (!mounted || key != dateKey(_date)) return;
      setState(() {
        _day = null;
        _comment = null;
        _loadingDay = false;
      });
    }
  }

  Future<void> _loadRange() async {
    final range = _range;
    if (_rangeDays != null) setState(() => _rangeDays = null);
    try {
      final results = await Future.wait<Object>([
        _remote.days(_uid, lastDays(DateTime.now(), range)),
        _remote.meta(_uid, 'weights'),
      ]);
      if (!mounted || range != _range) return;
      setState(() {
        _rangeDays = results[0] as Map<String, DayLog>;
        _weights = [for (final w in results[1] as List<Map<String, dynamic>>) WeightRecord.fromJson(w)];
      });
    } catch (e) {
      if (mounted && range == _range) setState(() => _rangeDays = const {});
    }
  }

  void _shift(int days) {
    setState(() => _date = DateTime(_date.year, _date.month, _date.day + days));
    _loadDay();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(now.year - 2), lastDate: dayOnly(now));
    if (d == null) return;
    setState(() => _date = dayOnly(d));
    await _loadDay();
  }

  Future<void> _editGoals() async {
    final me = AppScope.read(context).profile;
    final goals = await Navigator.push<Goals>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalsScreen(
          goals: _goals,
          title: 'Metas de ${widget.patient.name}',
          suggestion: (_profile?.hasMeasures ?? false) ? _profile!.suggestGoals() : null,
        ),
      ),
    );
    if (goals == null) return;
    final stamped = goals.stamped(by: me.name);
    try {
      await _remote.setPatientGoals(_uid, stamped);
      if (!mounted) return;
      setState(() => _goals = stamped);
      showSnack(context, 'Metas atualizadas. O paciente verá na próxima sincronização.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar as metas agora.');
    }
  }

  Future<void> _editComment() async {
    final me = AppScope.read(context).profile;
    final key = dateKey(_date);
    final ctrl = TextEditingController(text: _comment?.text ?? '');
    final textValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recado de ${friendlyDate(_date).toLowerCase()}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Escreva uma orientação para o paciente. Deixe vazio para apagar.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (textValue == null) return;
    final comment = DayComment(key, textValue, me.name);
    try {
      await _remote.setComment(_uid, comment);
      if (!mounted || key != dateKey(_date)) return;
      setState(() => _comment = textValue.isEmpty ? null : comment);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar o recado agora.');
    }
  }

  Widget _diaryTab() {
    final day = _day;
    return RefreshIndicator(
      onRefresh: _loadDay,
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
          if (_loadingDay)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else if (day == null)
            EmptyNote(
              icon: Icons.error_outline,
              text: 'Não foi possível carregar este dia.',
              action: 'Tentar de novo',
              onAction: _loadDay,
            )
          else
            DayView(day: day, goals: _goals, comment: _comment),
        ],
      ),
    );
  }

  Widget _summaryTab() {
    final days = _rangeDays;
    final p = _profile;
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _loadRange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 dias')),
              ButtonSegment(value: 30, label: Text('30 dias')),
            ],
            selected: {_range},
            onSelectionChanged: (s) {
              setState(() => _range = s.first);
              _loadRange();
            },
          ),
          const SizedBox(height: 12),
          if (days == null)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else
            SummaryView(dates: lastDays(DateTime.now(), _range), days: days, goals: _goals),
          const SizedBox(height: 12),
          WeightCard(weights: _weights),
          if (p != null && p.hasMeasures) ...[
            const SizedBox(height: 12),
            NvCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dados do paciente', style: text.titleMedium),
                  const SizedBox(height: 8),
                  Text('${p.sex == 'M' ? 'Masculino' : 'Feminino'} · ${DateTime.now().year - p.birthYear} anos · '
                      '${fmt(p.heightCm)} cm · ${fmt(p.weightKg, 1)} kg'),
                  Text('Atividade: ${p.activity.label} · Objetivo: ${p.objective.label}'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || _profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.patient.name)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : EmptyNote(icon: Icons.error_outline, text: _error!, action: 'Tentar de novo', onAction: _loadAll),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.patient.name),
          actions: [
            IconButton(tooltip: 'Metas do paciente', onPressed: _editGoals, icon: const Icon(Icons.flag_outlined)),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Diário'), Tab(text: 'Resumo')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _editComment,
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(_comment == null ? 'Deixar recado' : 'Editar recado'),
        ),
        body: TabBarView(children: [_diaryTab(), _summaryTab()]),
      ),
    );
  }
}
