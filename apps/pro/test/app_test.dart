import 'package:flutter_test/flutter_test.dart';
import 'package:nutrivitta_pro/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('abre na tela de entrada do NutriVitta Pro', (tester) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NutriVittaProApp());
    for (var i = 0; i < 40 && find.text('PRO').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('PRO'), findsOneWidget);
    expect(find.textContaining('Seus pacientes usam o app NutriVitta'), findsOneWidget);
  });
}
