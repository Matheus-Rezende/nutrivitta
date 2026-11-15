import 'package:flutter/material.dart';

import '../alerts.dart';
import '../app_info.dart';
import '../settings.dart';
import '../theme/nv_theme.dart';
import '../update/update_ui.dart';
import '../update/updater.dart';
import 'brand.dart';
import 'common.dart';

/// Configurações (comum aos dois apps): conta, aparência, notificações,
/// atualizações e informações do aplicativo.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.app,
    required this.settings,
    this.account,
    this.extra = const [],
  });

  final AppInfo app;
  final AppSettings settings;

  /// Seção da conta (cada app mostra a sua).
  final Widget? account;

  /// Seções próprias do app, antes de "Sobre o app".
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Configurações')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            if (account != null) ...[
              const SettingsHeader('Conta', Icons.account_circle_outlined),
              account!,
            ],
            const SettingsHeader('Aparência', Icons.palette_outlined),
            SettingsGroup(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tema', style: text.titleMedium),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
                          ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode)),
                        ],
                        selected: {s.themeMode},
                        onSelectionChanged: (v) => s.setThemeMode(v.first),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      switch (s.themeMode) {
                        ThemeMode.system => 'Segue o tema do celular: claro de dia e escuro quando o aparelho estiver no modo escuro.',
                        ThemeMode.dark => 'Fundo escuro, confortável à noite e econômico em telas OLED.',
                        ThemeMode.light => 'Fundo claro, mais fácil de ler sob luz forte.',
                      },
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SettingsDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cor de destaque', style: text.titleMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 4,
                      runSpacing: 8,
                      children: [
                        for (final a in Accent.values)
                          _AccentDot(accent: a, selected: s.accent == a, onTap: () => s.setAccent(a)),
                      ],
                    ),
                  ],
                ),
              ),
              const SettingsDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tamanho do texto', style: text.titleMedium),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<double>(
                        showSelectedIcon: false,
                        segments: [for (final (v, l) in textScales) ButtonSegment(value: v, label: Text(l))],
                        selected: {s.textScale},
                        onSelectionChanged: (v) => s.setTextScale(v.first),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            if (Alerts.supported) ...[
              const SettingsHeader('Notificações', Icons.notifications_outlined),
              _NotificationsGroup(app: app),
            ],
            if (Updater.instance.supported) ...[
              const SettingsHeader('Atualizações', Icons.system_update_outlined),
              const UpdatesCard(),
            ],
            ...extra,
            const SettingsHeader('Sobre o app', Icons.info_outline_rounded),
            AboutGroup(app: app),
          ],
        ),
      ),
    );
  }
}

class _NotificationsGroup extends StatefulWidget {
  const _NotificationsGroup({required this.app});

  final AppInfo app;

  @override
  State<_NotificationsGroup> createState() => _NotificationsGroupState();
}

class _NotificationsGroupState extends State<_NotificationsGroup> with WidgetsBindingObserver {
  bool? _permitted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await Alerts.permitted();
    if (mounted) setState(() => _permitted = p);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = widget.app;
    return SettingsGroup(children: [
      ListTile(
        leading: Icon(
          _permitted == false ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
          color: _permitted == false ? scheme.error : null,
        ),
        title: Text(_permitted == false ? 'Notificações bloqueadas' : 'Notificações permitidas'),
        subtitle: Text(_permitted == false
            ? 'Toque para permitir. Se nada acontecer, libere em Configurações do Android > Apps > ${app.name} > Notificações.'
            : app.pro
                ? 'Avisa quando um paciente aceita ou recusa o pedido de conexão.'
                : 'Avisa pedidos de conexão e recados do nutricionista.'),
        onTap: _permitted == false
            ? () async {
                await Alerts.requestPermission();
                await _load();
              }
            : null,
      ),
      const SettingsDivider(),
      const ListTile(
        leading: Icon(Icons.schedule_outlined),
        title: Text('Com que frequência'),
        subtitle: Text('Com o app aberto, a cada 15 segundos. Com o app fechado, o Android verifica mais ou menos '
            'a cada 15 minutos (pode atrasar em economia de bateria).'),
      ),
    ]);
  }
}

/// Informações do aplicativo: versão, novidades, privacidade e licenças.
class AboutGroup extends StatelessWidget {
  const AboutGroup({super.key, required this.app});

  final AppInfo app;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(children: [
      ListTile(
        leading: const NvLogo(size: 32),
        title: Text(app.name),
        subtitle: Text('Versão ${app.version}'),
      ),
      const SettingsDivider(),
      ListTile(
        leading: const Icon(Icons.new_releases_outlined),
        title: const Text('Novidades'),
        subtitle: const Text('O que mudou em cada versão'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangelogScreen())),
      ),
      const SettingsDivider(),
      ListTile(
        leading: const Icon(Icons.lock_outline_rounded),
        title: const Text('Privacidade'),
        subtitle: Text(app.privacy),
      ),
      const SettingsDivider(),
      const ListTile(
        leading: Icon(Icons.health_and_safety_outlined),
        title: Text('Aviso de saúde'),
        subtitle: Text('Os cálculos de calorias e as metas sugeridas são estimativas e não substituem a consulta '
            'com nutricionista ou médico.'),
      ),
      const SettingsDivider(),
      const ListTile(
        leading: Icon(Icons.menu_book_outlined),
        title: Text('Tabela de alimentos'),
        subtitle: Text('TACO - Tabela Brasileira de Composição de Alimentos, 4ª edição (NEPA/UNICAMP, 2011). '
            'Valores por 100 g.'),
      ),
      const SettingsDivider(),
      ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('Licenças'),
        subtitle: const Text('Flutter, pacotes, tabela TACO e fontes Barlow (SIL Open Font License)'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showLicensePage(
          context: context,
          applicationName: app.name,
          applicationVersion: app.version,
          applicationIcon: const Padding(padding: EdgeInsets.all(8), child: NvLogo(size: 48)),
        ),
      ),
    ]);
  }
}

/// Novidades de todas as versões (vem do CHANGELOG.md do app).
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novidades')),
      body: FutureBuilder<String>(
        future: DefaultAssetBundle.of(context).loadString('CHANGELOG.md'),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Não foi possível abrir as novidades.'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final md = snap.data!;
          final start = md.indexOf('\n## ');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [ReleaseNotes(start < 0 ? md : md.substring(start).replaceAll('\n## ', '\n## Versão '))],
          );
        },
      ),
    );
  }
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, this.icon, {super.key});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 14, endIndent: 14);
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.accent, required this.selected, required this.onTap});

  final Accent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? accentForDark(accent.color) : accent.color;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Cor ${accent.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: selected ? Icon(Icons.check_rounded, color: dark ? NvColors.night : Colors.white) : null,
                ),
                const SizedBox(height: 4),
                Text(accent.label, style: text.labelMedium, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
