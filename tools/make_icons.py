"""Gera os ícones dos apps (Android e iOS): folha branca sobre fundo verde
(NutriVitta) ou verde-azulado (NutriVitta Pro).

Uso: python3 tools/make_icons.py
Regrava cada PNG de ícone existente no tamanho que ele já tem.
"""
import glob
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GREEN = (30, 127, 79)
TEAL = (20, 102, 92)
ORANGE = (242, 140, 40)
WHITE = (255, 255, 255)


def quad(p0, p1, p2, n=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]


def draw_icon(size, bg=GREEN):
    s = size * 4  # desenha maior e reduz para suavizar
    img = Image.new('RGB', (s, s), bg)
    d = ImageDraw.Draw(img)
    # mesma folha do NvLogo, um pouco menor para caber na máscara redonda
    k, o = 0.72, 0.14

    def pt(x, y):
        return (s * (o + x * k), s * (o + y * k))

    a, b = pt(0.27, 0.75), pt(0.76, 0.24)
    leaf = quad(a, pt(0.20, 0.26), b) + quad(b, pt(0.80, 0.76), a)
    d.polygon(leaf, fill=WHITE)
    d.line([a, pt(0.62, 0.38)], fill=bg, width=max(2, int(s * 0.035 * k)))
    c, r = pt(0.73, 0.70), s * 0.07 * k
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=ORANGE)
    return img.resize((size, size), Image.LANCZOS)


def main():
    for app, bg in (('paciente', GREEN), ('pro', TEAL)):
        base = os.path.join(ROOT, 'apps', app)
        paths = glob.glob(os.path.join(base, 'android/app/src/main/res/mipmap-*/ic_launcher.png'))
        paths += glob.glob(os.path.join(base, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png'))
        for p in paths:
            size = Image.open(p).size[0]
            draw_icon(size, bg).save(p)
            print(size, os.path.relpath(p, ROOT))


if __name__ == '__main__':
    main()
