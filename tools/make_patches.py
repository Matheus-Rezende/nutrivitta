"""Gera os patches de atualização (só a diferença) e o update.json.

Uso: python make_patches.py <pasta_nova> <pasta_anterior> <versao> <app>

<app>: paciente ou pro.
<pasta_nova>: nutrivitta-<app>-v<versao>.apk (universal) e
nutrivitta-<app>-v<versao>-<abi>.apk para cada processador.
<pasta_anterior>: os APKs da versão anterior (podem faltar).
Cria os .patch e o update.json dentro de <pasta_nova>.
"""
import hashlib
import json
import os
import re
import sys

import bsdiff4

ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64']


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main(new_dir, prev_dir, version, app):
    base = f'nutrivitta-{app}-v{version}'
    apks = {}
    for abi in ABIS + ['universal']:
        name = f'{base}.apk' if abi == 'universal' else f'{base}-{abi}.apk'
        path = os.path.join(new_dir, name)
        if os.path.exists(path):
            apks[abi] = dict(name=name, size=os.path.getsize(path), sha256=sha256(path))
    patches = []
    if os.path.isdir(prev_dir):
        for prev in sorted(os.listdir(prev_dir)):
            if not prev.endswith('.apk'):
                continue
            m = re.search(r'-(arm64-v8a|armeabi-v7a|x86_64)\.apk$', prev)
            targets = [m.group(1)] if m else ABIS
            ppath = os.path.join(prev_dir, prev)
            psha = sha256(ppath)
            for abi in targets:
                if abi not in apks:
                    continue
                name = f'{base}-{abi}-from-{psha[:12]}.patch'
                out = os.path.join(new_dir, name)
                bsdiff4.file_diff(ppath, os.path.join(new_dir, apks[abi]['name']), out)
                # confere: o patch aplicado ao APK anterior tem que dar o APK novo exato
                check = out + '.check'
                bsdiff4.file_patch(ppath, check, out)
                ok = sha256(check) == apks[abi]['sha256']
                os.remove(check)
                if not ok:
                    raise SystemExit(f'Patch {name} não reproduz o APK novo')
                size = os.path.getsize(out)
                if size > apks[abi]['size'] * 0.8:
                    os.remove(out)  # não compensa: baixa o APK inteiro
                    continue
                patches.append(dict(name=name, size=size, fromSha256=psha, to=abi))
                print(f'{prev} -> {abi}: {size / 1e6:.1f} MB (APK {apks[abi]["size"] / 1e6:.1f} MB)')
    with open(os.path.join(new_dir, 'update.json'), 'w') as f:
        json.dump(dict(format=1, version=version, apks=apks, patches=patches), f, indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:5])
