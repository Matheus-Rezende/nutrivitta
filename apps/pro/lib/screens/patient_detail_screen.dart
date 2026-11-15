import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../pro_state.dart';

/// Ficha do paciente para o nutricionista: diário com fotos (só leitura),
/// resumo, medidas, anamnese, metas e recados.
class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key, required this.link});

  final Link link;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> with SingleTickerProviderStateMixin {
  final _remote = Remote.instance;
  late final _tabs = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));

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

  // medidas e anamnese
  List<BodyMeasure>? _measures;
  Anamnesis? _anamnesis;

  String get _uid => widget.link.patientUid;
  String get _me => ProScope.read(context).profile?.name ?? '';
  bool get _isToday => dateKey(_date) == dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
        _goals = g is Map ? Goals.fromJson(Map<String, dynamic>.from(g)) : _profile!.suggestGoals();
      });
      await Future.wait([_loadDay(), _loadRange(), _loadMeasures(), _loadAnamnesis()]);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir os dados deste paciente. Confira a internet. Se o problema '
            'continuar, peça para ele abrir o app NutriVitta (isso refaz a conexão) ou remova-o da lista e envie '
            'um pedido novo pelo código dele.');
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
        _remote.weights(_uid),
      ]);
      if (!mounted || range != _range) return;
      setState(() {
        _rangeDays = results[0] as Map<String, DayLog>;
        _weights = results[1] as List<WeightRecord>;
      });
    } catch (e) {
      if (mounted && range == _range) setState(() => _rangeDays = const {});
    }
  }

  Future<void> _loadMeasures() async {
    try {
      final m = await _remote.measures(_uid);
      if (mounted) setState(() => _measures = m);
    } catch (e) {
      if (mounted) setState(() => _measures = const []);
    }
  }

  Future<void> _loadAnamnesis() async {
    try {
      final a = await _remote.anamnesis(_uid);
      if (mounted) setState(() => _anamnesis = a);
    } catch (e) {
      if (mounted) setState(() => _anamnesis = const Anamnesis());
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
    final goals = await Navigator.push<Goals>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalsScreen(
          goals: _goals,
          title: 'Metas de ${widget.link.patientLabel}',
          suggestion: (_profile?.hasMeasures ?? false) ? _profile!.suggestGoals() : null,
        ),
      ),
    );
    if (goals == null || !mounted) return;
    final stamped = goals.stamped(by: _me);
    try {
      await _remote.saveGoals(_uid, stamped);
      if (!mounted) return;
      unawaited(_signal('goals'));
      setState(() => _goals = stamped);
      showSnack(context, 'Metas atualizadas. O paciente vê em alguns segundos com o app aberto.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar as metas agora.');
    }
  }

  Future<void> _editComment() async {
    final key = dateKey(_date);
    final ctrl = TextEditingController(text: _comment?.text ?? '');
    final value = await showDialog<String>(
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
    if (value == null || !mounted) return;
    final comment = DayComment(key, value, _me);
    try {
      await _remote.setComment(_uid, comment);
      if (!mounted) return;
      unawaited(_signal('comments'));
      if (key != dateKey(_date)) return;
      setState(() => _comment = value.isEmpty ? null : comment);
      if (value.isNotEmpty) showSnack(context, 'Recado salvo. O paciente recebe o aviso no app.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar o recado agora.');
    }
  }

  Future<void> _editMeasure(BodyMeasure? initial) async {
    final m = await Navigator.push<BodyMeasure>(
      context,
      MaterialPageRoute(builder: (_) => MeasureEditScreen(initial: initial, by: _me)),
    );
    if (m == null || !mounted) return;
    final list = BodyMeasure.upsert(_measures ?? const [], m);
    try {
      await _remote.saveMeasures(_uid, list);
      if (!mounted) return;
      unawaited(_signal('measures'));
      setState(() => _measures = list);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar as medidas agora.');
    }
  }

  /// Avisa o app do paciente para buscar os dados de novo.
  Future<void> _signal(String what) {
    final state = ProScope.read(context);
    return state.signalChange(state.current(widget.link), what);
  }

  Future<void> _askAnamnesis() async {
    final state = ProScope.read(context);
    try {
      await state.requestAnamnesis(state.current(widget.link));
      if (mounted) showSnack(context, 'Pedido enviado. O paciente recebe o aviso no app NutriVitta.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível enviar o pedido agora.');
    }
  }

  Future<void> _editAnamnesis() async {
    if (!ProScope.read(context).current(widget.link).canEditAnamnesis) {
      showSnack(context, 'A permissão para editar terminou. Peça de novo ao paciente.');
      return;
    }
    final a = await Navigator.push<Anamnesis>(
      context,
      MaterialPageRoute(
        builder: (_) => AnamnesisEditScreen(
            anamnesis: _anamnesis ?? const Anamnesis(), title: 'Anamnese de ${widget.link.patientLabel}'),
      ),
    );
    if (a == null || !mounted) return;
    final stamped = Anamnesis(a.answers, DateTime.now().toUtc().toIso8601String(), _me);
    try {
      await _remote.saveAnamnesis(_uid, stamped);
      if (!mounted) return;
      unawaited(_signal('anamnesis'));
      setState(() => _anamnesis = stamped);
    } on CloudException catch (e) {
      if (mounted) {
        showSnack(context,
            e.denied ? 'O paciente revogou a permissão ou ela terminou. Peça de novo.' : 'Não foi possível salvar a anamnese agora.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível salvar a anamnese agora.');
    }
  }

  Future<void> _end() async {
    final state = ProScope.read(context);
    final ok = await confirm(
      context,
      title: 'Encerrar acompanhamento?',
      text: 'Você deixará de ver os dados de ${widget.link.patientLabel} quando o app dele sincronizar. '
          'Para voltar, será preciso enviar um novo pedido.',
      ok: 'Encerrar',
    );
    if (!ok || !mounted) return;
    try {
      await state.close(widget.link);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível encerrar agora.');
    }
  }

  /// Tira o paciente da lista (o vínculo é apagado; dá para pedir de novo pelo código).
  Future<void> _remove() async {
    final state = ProScope.read(context);
    final ok = await confirm(
      context,
      title: 'Remover ${widget.link.patientLabel} da lista?',
      text: 'A conexão é desfeita. Para acompanhar de novo, envie um pedido novo com o código do paciente.',
      ok: 'Remover',
    );
    if (!ok || !mounted) return;
    try {
      await state.forget(state.current(widget.link));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível remover agora.');
    }
  }

  Widget _loading() => const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));

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
            _loading()
          else if (day == null)
            EmptyNote(
              icon: Icons.error_outline,
              text: 'Não foi possível carregar este dia.',
              action: 'Tentar de novo',
              onAction: _loadDay,
            )
          else
            DayView(
              day: day,
              goals: _goals,
              comment: _comment,
              loadPhoto: (meal) => _remote.photo(_uid, day.photoIdOf(meal)),
              photoCacheScope: _uid,
            ),
        ],
      ),
    );
  }

  Widget _summaryTab() {
    final days = _rangeDays;
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
            _loading()
          else
            SummaryView(dates: lastDays(DateTime.now(), _range), days: days, goals: _goals),
          const SizedBox(height: 12),
          WeightCard(weights: _weights),
          if (_profile != null) ...[
            const SizedBox(height: 12),
            ProfileSummary(profile: _profile!),
          ],
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Metas diárias'),
              subtitle: Text(
                  '${fmt(_goals.kcal)} kcal · P ${fmt(_goals.protein)} g · C ${fmt(_goals.carbs)} g · G ${fmt(_goals.fat)} g'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editGoals,
            ),
          ),
        ],
      ),
    );
  }

  Widget _measuresTab() {
    final m = _measures;
    return RefreshIndicator(
      onRefresh: _loadMeasures,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (m == null) _loading() else MeasuresView(measures: m, onAdd: () => _editMeasure(null), onTap: _editMeasure),
        ],
      ),
    );
  }

  Widget _anamnesisTab() {
    final a = _anamnesis;
    final link = ProScope.of(context).current(widget.link);
    return RefreshIndicator(
      onRefresh: _loadAnamnesis,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AnamnesisPermission(link: link, onAsk: _askAnamnesis),
          const SizedBox(height: 12),
          if (a == null) _loading() else AnamnesisView(anamnesis: a, onEdit: link.canEditAnamnesis ? _editAnamnesis : null),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.link.patientLabel;
    if (_error != null || _profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmptyNote(icon: Icons.error_outline, text: _error!, action: 'Tentar de novo', onAction: _loadAll),
                      TextButton.icon(
                        onPressed: _remove,
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Remover da lista'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(tooltip: 'Metas do paciente', onPressed: _editGoals, icon: const Icon(Icons.flag_outlined)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'end') _end();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'end', child: Text('Encerrar acompanhamento'))],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [Tab(text: 'Diário'), Tab(text: 'Resumo'), Tab(text: 'Medidas'), Tab(text: 'Anamnese')],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _editComment,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(_comment == null ? 'Deixar recado' : 'Editar recado'),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [_diaryTab(), _summaryTab(), _measuresTab(), _anamnesisTab()],
      ),
    );
  }
}

/// Situação da permissão para editar a anamnese, com o botão de pedir.
class _AnamnesisPermission extends StatelessWidget {
  const _AnamnesisPermission({required this.link, required this.onAsk});

  final Link link;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final until = link.anamnesisUntilTime;
    final (IconData icon, Color? color, String title, String body) = link.canEditAnamnesis
        ? (
            Icons.lock_open_rounded,
            scheme.primaryContainer,
            'Você pode editar a anamnese',
            'O paciente permitiu até ${shortDate(until!)} às ${hourMinute(until)}. Ele pode revogar antes.',
          )
        : link.anamnesisRequest == 'pending'
            ? (
                Icons.hourglass_top_rounded,
                null,
                'Aguardando o paciente',
                'O pedido para editar a anamnese foi enviado. A resposta aparece aqui sozinha.',
              )
            : link.anamnesisRequest == 'denied'
                ? (
                    Icons.lock_outline_rounded,
                    null,
                    'Edição não permitida',
                    'O paciente não permitiu (ou revogou) a edição. Você continua vendo a anamnese.',
                  )
                : (
                    Icons.lock_outline_rounded,
                    null,
                    'Somente leitura',
                    'Para alterar as respostas, peça permissão ao paciente. Ela vale por 24 horas.',
                  );
    final canAsk = !link.canEditAnamnesis && link.anamnesisRequest != 'pending';
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: text.bodyMedium),
            if (canAsk) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAsk,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(link.anamnesisRequest == 'denied' ? 'Pedir de novo' : 'Pedir permissão para editar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
