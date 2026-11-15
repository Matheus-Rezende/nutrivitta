import 'package:flutter/material.dart';

import '../theme/nv_theme.dart';
import 'updater.dart';

/// Procura atualizações ao abrir o app e ao voltar para ele, e avisa quando há
/// uma versão nova.
class UpdateWatcher extends StatefulWidget {
  const UpdateWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher> with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final up = Updater.instance;
    if (!up.supported || _showing) return;
    final info = await up.check();
    if (info == null || !mounted || _showing || await up.isSnoozed(info)) return;
    if (!mounted) return;
    _showing = true;
    final later = await showUpdateSheet(context);
    _showing = false;
    if (later) await up.snooze(info);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Chave do navegador do app, para abrir a janela da atualização a partir do
/// aviso flutuante (que fica acima de todas as telas).
final updateNavigatorKey = GlobalKey<NavigatorState>();

/// Mostra a versão nova com as novidades. Retorna true se a pessoa escolheu "Depois".
Future<bool> showUpdateSheet(BuildContext context) async {
  final up = Updater.instance;
  up.setSheetOpen(true);
  try {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _UpdateSheet(),
    );
    return r ?? true;
  } finally {
    up.setSheetOpen(false);
  }
}

/// Aviso flutuante enquanto a atualização baixa: aparece em qualquer tela
/// quando a pessoa fecha a janela e continua usando o app. Tocar nele abre a
/// janela de novo.
class UpdateProgressBanner extends StatelessWidget {
  const UpdateProgressBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final up = Updater.instance;
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: up,
          builder: (context, _) {
            final u = up.available;
            final failed = up.stage == UpdateStage.failed && up.downloadFailed;
            final show = up.supported && u != null && !up.sheetOpen && (up.busy || failed);
            final bottom = MediaQuery.of(context).padding.bottom + 92;
            return AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              left: 16,
              right: 16,
              bottom: show ? bottom : -120,
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: show ? 1 : 0,
                  child: u == null ? const SizedBox.shrink() : _BannerCard(info: u, failed: failed),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.info, required this.failed});

  final UpdateInfo info;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final up = Updater.instance;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final installing = up.stage == UpdateStage.installing;
    final pct = ((up.progress ?? 0) * 100).round();
    final title = failed
        ? 'A atualização não terminou'
        : installing
            ? 'Abrindo o instalador da versão ${info.version}…'
            : 'Baixando a versão ${info.version}… $pct%';
    final subtitle = failed ? 'Toque para tentar de novo' : 'Pode continuar usando o app. Toque para ver detalhes.';
    return Material(
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final ctx = updateNavigatorKey.currentContext;
          if (ctx != null) showUpdateSheet(ctx);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: failed ? NvColors.red : NvColors.orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      failed ? Icons.error_outline_rounded : Icons.downloading_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              if (!failed) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: installing ? null : up.progress, minHeight: 6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context) {
    final up = Updater.instance;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: up,
      builder: (context, _) {
        final u = up.available;
        if (u == null) {
          return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('O app está atualizado.')));
        }
        final busy = up.stage == UpdateStage.downloading || up.stage == UpdateStage.installing;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: NvColors.orange, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.system_update_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nova versão ${u.version}', style: text.headlineSmall),
                            Text('Você está na ${Updater.app.version}${u.apkSize > 0 ? ' · download de ${u.sizeLabel}${u.isPatch ? ' (só o que mudou)' : ''}' : ''}',
                                style: text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (u.notes.isNotEmpty)
                    Flexible(
                      child: SingleChildScrollView(child: ReleaseNotes(u.notes)),
                    ),
                  const SizedBox(height: 12),
                  if (up.stage == UpdateStage.downloading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: up.progress, minHeight: 8),
                    ),
                    const SizedBox(height: 6),
                    Text('Baixando… ${((up.progress ?? 0) * 100).round()}%', style: text.bodySmall),
                    const SizedBox(height: 8),
                  ],
                  if (up.message != null && up.stage == UpdateStage.failed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(up.message!, style: text.bodyMedium?.copyWith(color: NvColors.red)),
                    ),
                  Text(
                    'Seus dados continuam salvos. O Android vai pedir para confirmar a instalação.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy ? null : up.downloadAndInstall,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(up.stage == UpdateStage.failed ? 'Tentar de novo' : 'Atualizar agora'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(busy ? 'Continuar usando o app' : 'Depois'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mostra as notas da versão (um markdown simples: títulos e listas).
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final children = <Widget>[];
    for (final raw in markdown.split('\n')) {
      final line = raw.trim().replaceAll('**', '').replaceAll('`', '');
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(line.replaceFirst(RegExp(r'^#+\s*'), ''), style: text.titleMedium),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: 8),
                child: Icon(Icons.circle, size: 6, color: NvColors.green),
              ),
              Expanded(child: Text(line.substring(2), style: text.bodyMedium)),
            ],
          ),
        ));
      } else {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line, style: text.bodyMedium)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// Cartão da seção Atualizações nas Configurações.
class UpdatesCard extends StatelessWidget {
  const UpdatesCard({super.key});

  String _when(DateTime? t) {
    if (t == null) return 'ainda não procurou';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora há pouco';
    if (d.inHours < 1) return 'há ${d.inMinutes} min';
    if (d.inDays < 1) return 'há ${d.inHours} h';
    return 'há ${d.inDays} dia${d.inDays == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final up = Updater.instance;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: up,
      builder: (context, _) {
        final u = up.available;
        final checking = up.stage == UpdateStage.checking;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          decoration: BoxDecoration(
            color: u != null ? NvColors.orange : scheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_rounded, color: u != null ? Colors.white : scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u != null ? 'Versão ${u.version} disponível' : 'Atualizações',
                            style: text.titleMedium?.copyWith(color: u != null ? Colors.white : null)),
                        Text(
                          u != null
                              ? 'Você está na ${Updater.app.version}'
                              : 'Versão ${Updater.app.version} · última busca ${_when(up.lastCheck)}',
                          style: text.bodySmall?.copyWith(color: u != null ? Colors.white : null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (up.message != null && u == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  child: Text(up.message!, style: text.bodySmall?.copyWith(color: NvColors.red)),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (u != null)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: NvColors.ink),
                      onPressed: () => showUpdateSheet(context),
                      child: const Text('Ver e atualizar'),
                    )
                  else
                    OutlinedButton(
                      onPressed: checking
                          ? null
                          : () async {
                              final found = await up.check(force: true);
                              if (found == null && context.mounted && up.message == null) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Você já está na versão mais nova.')));
                              }
                            },
                      child: Text(checking ? 'Procurando…' : 'Procurar agora'),
                    ),
                  const Spacer(),
                  if (u == null) ...[
                    Text('Avisar sozinho', style: text.bodySmall),
                    Switch(value: up.autoCheck, onChanged: up.setAutoCheck),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
