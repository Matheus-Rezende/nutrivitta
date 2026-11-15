import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';
import '../sync.dart';

/// Pedidos de conexão recebidos e nutricionistas conectados.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  String? _working;

  Future<void> _answer(Link link, LinkStatus status) async {
    final who = link.proName.isEmpty ? 'o nutricionista' : link.proName;
    if (status == LinkStatus.accepted) {
      final ok = await confirm(
        context,
        title: 'Conectar com $who?',
        text: '$who poderá ver seu diário alimentar com as fotos, peso, medidas, anamnese e dados do perfil, '
            'ajustar suas metas e deixar recados. Você pode desfazer a conexão quando quiser.',
        ok: 'Aceitar',
      );
      if (!ok) return;
    } else if (status == LinkStatus.ended) {
      final ok = await confirm(
        context,
        title: 'Desconectar de $who?',
        text: '$who deixará de ver seus dados. Os seus registros continuam com você.',
        ok: 'Desconectar',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _working = link.id);
    try {
      await Sync.instance.answer(link, status);
      if (!mounted) return;
      showSnack(
          context,
          switch (status) {
            LinkStatus.accepted => 'Pronto! $who já pode acompanhar seu diário.',
            LinkStatus.declined => 'Pedido recusado.',
            _ => 'Conexão desfeita.',
          });
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível responder agora. Confira a internet e tente de novo.');
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _anamnesis(Link link, {required bool grant, bool revoke = false}) async {
    final who = link.proName.isEmpty ? 'o nutricionista' : link.proName;
    if (grant) {
      final ok = await confirm(
        context,
        title: 'Permitir que $who edite sua anamnese?',
        text: 'A permissão vale por 24 horas. Você pode revogar antes disso nesta tela.',
        ok: 'Permitir',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _working = 'anam:${link.id}');
    try {
      await Sync.instance.answerAnamnesis(link, grant: grant);
      if (!mounted) return;
      showSnack(
          context,
          grant
              ? '$who pode editar sua anamnese pelas próximas 24 horas.'
              : revoke
                  ? 'Permissão revogada.'
                  : 'Pedido recusado.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível responder agora. Confira a internet e tente de novo.');
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final account = Account.instance;
    final pending = state.pendingLinks;
    final connected = state.connectedLinks;
    final anamnesis = state.pendingAnamnesis;
    return Scaffold(
      appBar: AppBar(title: const Text('Nutricionistas')),
      body: RefreshIndicator(
        onRefresh: Sync.instance.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (!account.online)
              const EmptyNote(
                icon: Icons.cloud_off_outlined,
                text: 'Entre com a conta Google (em Perfil) para receber pedidos de conexão do seu nutricionista.',
              )
            else ...[
              _CodeCard(code: state.profile.code),
              if (pending.isNotEmpty) const SectionTitle('Pedidos de conexão', icon: Icons.mark_email_unread_outlined),
              for (final l in pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NvCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l.proName.isEmpty ? 'Nutricionista' : l.proName, style: text.titleMedium),
                        if (l.proCrn.isNotEmpty) Text(l.proCrn, style: text.bodySmall),
                        if (l.message.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('"${l.message}"', style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                        ],
                        const SizedBox(height: 12),
                        if (_working == l.id)
                          const Center(child: CircularProgressIndicator())
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                    onPressed: () => _answer(l, LinkStatus.declined), child: const Text('Recusar')),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                    onPressed: () => _answer(l, LinkStatus.accepted), child: const Text('Aceitar')),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (anamnesis.isNotEmpty) const SectionTitle('Pedidos para editar a anamnese', icon: Icons.assignment_outlined),
              for (final l in anamnesis)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NvCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${l.proName.isEmpty ? 'Seu nutricionista' : l.proName} quer editar sua anamnese',
                            style: text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Se você permitir, ele poderá alterar as respostas sobre rotina, alimentação e saúde pelas '
                          'próximas 24 horas. Ele continua vendo a anamnese mesmo se você não permitir.',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        if (_working == 'anam:${l.id}')
                          const Center(child: CircularProgressIndicator())
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                    onPressed: () => _anamnesis(l, grant: false), child: const Text('Não permitir')),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                    onPressed: () => _anamnesis(l, grant: true), child: const Text('Permitir')),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              const SectionTitle('Conectados', icon: Icons.verified_user_outlined),
              if (connected.isEmpty)
                Text('Nenhum nutricionista acompanha seus dados agora.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, l) in connected.indexed) ...[
                        if (i > 0) const Divider(),
                        ListTile(
                          leading: const Icon(Icons.medical_information_outlined),
                          title: Text(l.proName.isEmpty ? 'Nutricionista' : l.proName),
                          subtitle: Text([
                            if (l.proCrn.isNotEmpty) l.proCrn,
                            l.canEditAnamnesis
                                ? 'Pode editar a anamnese até ${shortDate(l.anamnesisUntilTime!)} às ${hourMinute(l.anamnesisUntilTime!)}'
                                : 'Vê a anamnese, sem editar',
                          ].join('\n')),
                          isThreeLine: l.proCrn.isNotEmpty,
                          trailing: _working == l.id
                              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(
                                  onPressed: () => _answer(l, LinkStatus.ended), child: const Text('Desconectar')),
                        ),
                        if (l.canEditAnamnesis)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(56, 0, 12, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _working == 'anam:${l.id}'
                                  ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                  : OutlinedButton.icon(
                                      onPressed: () => _anamnesis(l, grant: false, revoke: true),
                                      icon: const Icon(Icons.lock_outline, size: 18),
                                      label: const Text('Revogar edição da anamnese'),
                                    ),
                            ),
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

/// Código do paciente, para passar ao nutricionista.
class _CodeCard extends StatefulWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> {
  bool _busy = false;

  Future<void> _renew() async {
    final ok = await confirm(
      context,
      title: 'Gerar um código novo?',
      text: 'O código atual deixa de funcionar. Nutricionistas já conectados continuam conectados.',
      ok: 'Gerar novo',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await Sync.instance.newCode();
      if (mounted) showSnack(context, 'Código novo gerado.');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível gerar agora. Confira a internet e tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final code = widget.code;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seu código', style: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            if (code.isEmpty)
              Text('Gerando... (precisa de internet)', style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer))
            else
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      Remote.formatCode(code),
                      style: TextStyle(
                        fontFamily: display,
                        fontWeight: FontWeight.w800,
                        fontSize: 34,
                        letterSpacing: 3,
                        height: 1.1,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar código',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: Remote.formatCode(code)));
                      if (context.mounted) showSnack(context, 'Código copiado.');
                    },
                    icon: Icon(Icons.copy, color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              'Passe este código ao seu nutricionista. Ele envia o pedido pelo app NutriVitta Pro e só vê seus dados '
              'depois que você aceitar. Seu e-mail não é mostrado a ele.',
              style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton(
                        onPressed: _renew,
                        child: Text('Gerar código novo', style: TextStyle(color: scheme.onPrimaryContainer)),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
