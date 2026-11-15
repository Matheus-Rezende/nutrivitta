import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

import '../state/app_state.dart';

/// Busca a foto do prato: a que ainda está no aparelho ou a que já subiu.
Future<String?> loadMealPhoto(AppState state, String date, Meal meal) async {
  final id = DayLog.photoId(date, meal);
  final local = state.localPhoto(id);
  if (local != null) return local;
  final uid = Account.instance.uid;
  if (!Account.instance.online || uid == null) return null;
  return Remote.instance.photo(uid, id);
}

/// Opções da foto do prato de uma refeição: tirar, escolher, ver ou remover.
Future<void> showMealPhotoSheet(BuildContext context, {required String date, required Meal meal}) async {
  final state = AppScope.read(context);
  final has = state.day(date).hasPhoto(meal);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text('Foto do prato · ${meal.label}', style: Theme.of(ctx).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Fotografe o prato inteiro, com tudo o que vai comer nesta refeição.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          if (has)
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Ver foto'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(has ? 'Tirar outra foto' : 'Tirar foto'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (has)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Remover foto', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'view':
      final d = state.day(date);
      await showMealPhoto(
        context,
        title: '${meal.label} · ${friendlyDate(DateTime.parse(date))}',
        load: () => loadMealPhoto(state, date, meal),
        cacheKey: 'me/${d.photoIdOf(meal)}/${d.photos[meal]}',
      );
    case 'remove':
      state.removeMealPhoto(date, meal);
      showSnack(context, 'Foto do ${meal.label.toLowerCase()} removida.');
    case 'camera':
    case 'gallery':
      final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
      try {
        final x = await ImagePicker().pickImage(source: source, maxWidth: 720, maxHeight: 720, imageQuality: 55);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        if (!context.mounted) return;
        if (bytes.length > 600000) {
          showSnack(context, 'A foto ficou grande demais. Tente outra.');
          return;
        }
        state.setMealPhoto(date, meal, base64Encode(bytes));
        showSnack(context, 'Foto do prato salva em ${meal.label}.');
      } catch (e) {
        if (context.mounted) showSnack(context, 'Não foi possível abrir a câmera ou a galeria.');
      }
  }
}
