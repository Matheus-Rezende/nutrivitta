import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutrivitta_core/nutrivitta_core.dart';
import 'package:nutrivitta_paciente/version.dart';

void main() {
  test('versão do app igual à do pubspec.yaml e com novidades no CHANGELOG', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pub)!.group(1);
    expect(kAppVersion, v);
    expect(File('CHANGELOG.md').readAsStringSync(), contains('## $kAppVersion'));
  });

  test('releases: só as deste app, e a mais nova', () {
    Map<String, dynamic> rel(String tag) => {
          'tag_name': tag,
          'body': '- novidade\n\n## Como instalar no Android\n...',
          'assets': [
            {'name': kApp.apkFor(tag.substring(tag.indexOf('-v') + 2)), 'browser_download_url': 'https://x/$tag.apk', 'size': 10},
          ],
        };
    final mine = parseRelease(rel('${kApp.id}-v9.9.9'), kApp);
    expect(mine?.version, '9.9.9');
    expect(mine?.notes, '- novidade');
    expect(parseRelease(rel('${kApp.id == 'pro' ? 'paciente' : 'pro'}-v9.9.9'), kApp), isNull);
    expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
  });
}
