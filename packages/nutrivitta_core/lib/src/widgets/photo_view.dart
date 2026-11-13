import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Mostra a foto de uma refeição (JPEG em base64), carregada sob demanda.
/// As fotos já vistas ficam em memória enquanto o app está aberto.
Future<void> showMealPhoto(BuildContext context, {required String title, required Future<String?> Function() load}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(ctx).textTheme.titleMedium, maxLines: 2)),
                IconButton(tooltip: 'Fechar', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          MealPhoto(load: load),
        ],
      ),
    ),
  );
}

final _cache = <String, Uint8List>{};

/// Foto carregada de [load], com aviso de carregamento e de erro.
class MealPhoto extends StatefulWidget {
  const MealPhoto({super.key, required this.load, this.cacheKey});

  final Future<String?> Function() load;
  final String? cacheKey;

  @override
  State<MealPhoto> createState() => _MealPhotoState();
}

class _MealPhotoState extends State<MealPhoto> {
  late Future<Uint8List?> _future = _get();

  Future<Uint8List?> _get() async {
    final key = widget.cacheKey;
    if (key != null && _cache.containsKey(key)) return _cache[key];
    final b64 = await widget.load();
    if (b64 == null) return null;
    final bytes = base64Decode(b64);
    if (key != null) _cache[key] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return SizedBox(
            height: 160,
            child: Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _future = _get()),
                icon: const Icon(Icons.refresh),
                label: const Text('Não foi possível carregar a foto. Tentar de novo'),
              ),
            ),
          );
        }
        return InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true));
      },
    );
  }
}
