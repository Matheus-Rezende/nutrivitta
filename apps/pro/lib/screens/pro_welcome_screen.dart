import 'package:flutter/material.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';

/// Primeira tela do NutriVitta Pro: entrar ou criar conta.
class ProWelcomeScreen extends StatelessWidget {
  const ProWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScreen(
      pro: true,
      intro: 'Acompanhe o que seus pacientes comem e quando comem, com fotos das refeições, '
          'medidas, anamnese, metas e recados.',
      footer: [
        Text(
          'Seus pacientes usam o app NutriVitta. Eles só aparecem para você depois de aceitar o seu pedido de conexão.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
