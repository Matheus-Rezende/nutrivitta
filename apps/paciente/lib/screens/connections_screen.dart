import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final account = Account.instance;
    final pending = state.pendingLinks;
    final connected = state.connectedLinks;
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
              Text(
                'Seu nutricionista envia o pedido pelo app NutriVitta Pro usando o seu e-mail '
                '(${account.email}). Ele só vê seus dados depois que você aceitar.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
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
                          subtitle: l.proCrn.isEmpty ? null : Text(l.proCrn),
                          trailing: _working == l.id
                              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(
                                  onPressed: () => _answer(l, LinkStatus.ended), child: const Text('Desconectar')),
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
