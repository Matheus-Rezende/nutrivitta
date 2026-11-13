import 'package:flutter/material.dart';

import '../theme/nv_theme.dart';
import '../util/format.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: scheme.primary), const SizedBox(width: 8)],
          Text(text, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

/// Cartão com espaçamento interno padrão.
class NvCard extends StatelessWidget {
  const NvCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

/// Barra de progresso de um macronutriente: consumido / meta.
class MacroBar extends StatelessWidget {
  const MacroBar({super.key, required this.label, required this.value, required this.goal, required this.color});

  final String label;
  final double value;
  final double goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ratio = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 6),
        Text('${fmt(value)} / ${fmt(goal)} g', style: text.bodySmall),
      ],
    );
  }
}

/// Anel das calorias do dia.
class CalorieRing extends StatelessWidget {
  const CalorieRing({super.key, required this.kcal, required this.goal, this.size = 132});

  final double kcal;
  final double goal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = goal > 0 && kcal > goal * 1.05;
    final ratio = goal <= 0 ? 0.0 : (kcal / goal).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: '${fmt(kcal)} de ${fmt(goal)} quilocalorias',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 11,
                strokeCap: StrokeCap.round,
                color: over ? NvColors.orange : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmt(kcal),
                      style: TextStyle(
                          fontFamily: display, fontWeight: FontWeight.w800, fontSize: size * 0.27, height: 1, color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text('de ${fmt(goal)} kcal', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo numérico com rótulo e unidade.
class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.controller, required this.label, this.suffix, this.onChanged, this.autofocus = false});

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }
}

/// Aviso de tela vazia ou de erro, com ação opcional.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.icon, required this.text, this.action, this.onAction});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}

/// Pede uma confirmação simples.
Future<bool> confirm(BuildContext context, {required String title, required String text, String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
