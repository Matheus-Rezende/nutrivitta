import 'package:flutter_test/flutter_test.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:nutrivitta_paciente/main.dart';
import 'package:nutrivitta_paciente/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('abre, faz o cadastro sem conta e registra no diário', (tester) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NutriVittaApp());
    final local = find.text('Usar sem conta neste aparelho');
    await _pumpUntil(tester, local);
    expect(local, findsOneWidget);
    await tester.tap(local);
    await tester.pumpAndSettle();
    expect(find.text('Sobre você'), findsOneWidget);

    final state = AppScope.read(tester.element(find.text('Sobre você')));
    state.finishOnboarding(
      const Profile(name: 'Ana', sex: 'F', birthYear: 1995, heightCm: 165, weightKg: 62),
      const Goals(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diário'), findsOneWidget);
    expect(find.text('Café da manhã'), findsOneWidget);

    const per100 = Nutrients(kcal: 124, protein: 2.6, carbs: 25.8, fat: 1);
    state.addEntry(FoodEntry(
        id: 'x1',
        time: DateTime.now(),
        meal: Meal.lunch,
        foodId: 'taco:1',
        name: 'Arroz',
        grams: 200,
        nutrients: per100.scale(2)));
    await tester.pumpAndSettle();
    expect(find.text('248 kcal'), findsWidgets);
    expect(state.dirty, contains(AppState.dirtyDay(dateKey(DateTime.now()))));
  });

  testWidgets('pedido de conexão aparece no diário e no perfil', (tester) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NutriVittaApp());
    final local = find.text('Usar sem conta neste aparelho');
    await _pumpUntil(tester, local);
    await tester.tap(local);
    await tester.pumpAndSettle();
    final state = AppScope.read(tester.element(find.text('Sobre você')));
    state.finishOnboarding(const Profile(name: 'Ana'), const Goals());
    state.setLinks(const [Link(proUid: 'p1', patientUid: 'u1', proName: 'Dra. Bia', proCrn: 'CRN-3 123')]);
    await tester.pumpAndSettle();
    expect(find.text('Dra. Bia quer acompanhar sua alimentação'), findsOneWidget);
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('1 pedido de conexão aguardando você'), findsOneWidget);

    state.saveMeasure(const BodyMeasure('2026-11-01', {'waist': 80}));
    state.setAnamnesis(const Anamnesis({'goal': 'Mais energia'}));
    expect(state.dirty, containsAll([AppState.dirtyMeasures, AppState.dirtyAnamnesis]));
    expect(state.exportBackup()['measures'], isNotEmpty);
  });
}
