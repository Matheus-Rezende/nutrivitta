import 'package:flutter/material.dart';

import '../theme/nv_theme.dart';

/// Marca do NutriVitta: uma folha branca sobre um círculo verde.
class NvLogo extends StatelessWidget {
  const NvLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(dimension: size, child: CustomPaint(painter: _LogoPainter()));
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, s * 0.5, Paint()..color = NvColors.green);
    final a = Offset(s * 0.27, s * 0.75);
    final b = Offset(s * 0.76, s * 0.24);
    final leaf = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(s * 0.20, s * 0.26, b.dx, b.dy)
      ..quadraticBezierTo(s * 0.80, s * 0.76, a.dx, a.dy)
      ..close();
    canvas.drawPath(leaf, Paint()..color = Colors.white);
    canvas.drawLine(
        a,
        Offset(s * 0.62, s * 0.38),
        Paint()
          ..color = NvColors.green
          ..strokeWidth = s * 0.035
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(s * 0.73, s * 0.70), s * 0.07, Paint()..color = NvColors.orange);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}

/// Logo com o nome, para cabeçalhos. No app do nutricionista, [pro] mostra o selo PRO.
class NvWordmark extends StatelessWidget {
  const NvWordmark({super.key, this.size = 32, this.pro = false});

  final double size;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NvLogo(size: size),
        SizedBox(width: size * 0.3),
        Text(
          'NutriVitta',
          style: TextStyle(fontFamily: display, fontWeight: FontWeight.w800, fontSize: size * 0.75, color: ink, height: 1),
        ),
        if (pro) ...[
          SizedBox(width: size * 0.2),
          Container(
            padding: EdgeInsets.symmetric(horizontal: size * 0.15, vertical: size * 0.04),
            decoration: BoxDecoration(color: NvColors.orange, borderRadius: BorderRadius.circular(size * 0.15)),
            child: Text('PRO',
                style: TextStyle(
                    fontFamily: display, fontWeight: FontWeight.w800, fontSize: size * 0.4, color: Colors.white, height: 1.1)),
          ),
        ],
      ],
    );
  }
}
