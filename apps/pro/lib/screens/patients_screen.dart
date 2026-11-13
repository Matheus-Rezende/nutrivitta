import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../pro_state.dart';
import 'patient_detail_screen.dart';

/// Pacientes conectados, pedidos aguardando resposta e recusados.
class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  Future<void> _invite(BuildContext context) async {
    final state = ProScope.read(context);
    final email = TextEditingController();
    final message = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar paciente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail Google do paciente',
                  helperText: 'O mesmo que ele usa para entrar no app NutriVitta.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: message,
                maxLength: 200,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Mensagem (opcional)', hintText: 'Ex.: Olá! Sou sua nutricionista...'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar pedido')),
        ],
      ),
    );
    final mail = email.text.trim();
    if (go != true || !context.mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
      showSnack(context, 'Confira o e-mail digitado.');
      return;
    }
    try {
      final r = await state.invite(mail, message.text);
      if (!context.mounted) return;
      showSnack(
        context,
        switch (r) {
          InviteResult.sent => 'Pedido enviado. O paciente recebe o aviso no app NutriVitta.',
          InviteResult.notFound =>
            'Nenhum paciente com este e-mail no NutriVitta. Peça para ele instalar o app e entrar com a conta Google.',
          InviteResult.alreadyConnected => 'Este paciente já está conectado com você.',
          InviteResult.alreadyPending => 'Já existe um pedido aguardando a resposta deste paciente.',
          InviteResult.self => 'Este é o seu próprio e-mail.',
        },
      );
    } catch (e) {
      if (context.mounted) showSnack(context, 'Não foi possível enviar agora. Confira a internet e tente de novo.');
    }
  }

  Future<void> _manage(BuildContext context, Link l) async {
    final state = ProScope.read(context);
    final closeLabel = l.pending ? 'Cancelar pedido' : 'Remover da lista';
    final ok = await confirm(
      context,
      title: closeLabel,
      text: l.pending
          ? 'O pedido para ${l.patientLabel} será cancelado.'
          : 'O pedido para ${l.patientLabel} sai da sua lista. Você pode enviar outro depois.',
      ok: closeLabel,
    );
    if (!ok) return;
    try {
      if (l.pending) {
        await state.close(l);
      } else {
        await state.forget(l);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Não foi possível concluir agora.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ProScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final patients = state.patients;
    final waiting = state.waiting;
    final declined = state.declined;
    return Scaffold(
      appBar: AppBar(title: const NvWordmark(size: 28, pro: true)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _invite(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Adicionar paciente'),
      ),
      body: RefreshIndicator(
        onRefresh: state.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(state.error!, style: text.bodyMedium?.copyWith(color: scheme.error)),
              ),
            const SectionTitle('Pacientes', icon: Icons.groups_outlined),
            if (state.loadingLinks && state.links.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (patients.isEmpty)
              const EmptyNote(
                icon: Icons.person_add_alt,
                text: 'Nenhum paciente conectado ainda. Toque em "Adicionar paciente" e informe o e-mail Google dele.',
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, l) in patients.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Text(l.patientLabel.isEmpty ? '?' : l.patientLabel.characters.first.toUpperCase(),
                              style: TextStyle(color: scheme.onPrimaryContainer)),
                        ),
                        title: Text(l.patientLabel),
                        subtitle: l.patientName.isEmpty ? null : Text(l.patientEmail),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => PatientDetailScreen(link: l))),
                      ),
                    ],
                  ],
                ),
              ),
            if (waiting.isNotEmpty) ...[
              const SectionTitle('Aguardando resposta', icon: Icons.hourglass_top),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, l) in waiting.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        leading: const Icon(Icons.mark_email_read_outlined),
                        title: Text(l.patientLabel),
                        subtitle: Text(l.updatedAt.isEmpty
                            ? 'Pedido enviado'
                            : 'Pedido enviado ${friendlyDate(DateTime.parse(l.updatedAt).toLocal()).toLowerCase()}'),
                        trailing: IconButton(
                            tooltip: 'Cancelar pedido', onPressed: () => _manage(context, l), icon: const Icon(Icons.close)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (declined.isNotEmpty) ...[
              const SectionTitle('Recusados', icon: Icons.block),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, l) in declined.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        leading: const Icon(Icons.person_off_outlined),
                        title: Text(l.patientLabel),
                        subtitle: const Text('O paciente recusou o pedido'),
                        trailing: IconButton(
                            tooltip: 'Remover da lista',
                            onPressed: () => _manage(context, l),
                            icon: const Icon(Icons.delete_outline)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
