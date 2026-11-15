import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Aplica um patch no formato BSDIFF40 (o do bsdiff/bsdiff4) a [old] e
/// devolve o arquivo novo. Usado para montar o APK novo a partir do APK
/// instalado, baixando só a diferença.
Uint8List bspatch(Uint8List old, Uint8List patch) {
  if (patch.length < 32 || String.fromCharCodes(patch.sublist(0, 8)) != 'BSDIFF40') {
    throw const FormatException('Patch inválido');
  }
  int off(int at) {
    // inteiro de 64 bits com sinal na forma "sinal e magnitude", little endian
    var y = patch[at + 7] & 0x7f;
    for (var i = 6; i >= 0; i--) {
      y = y * 256 + patch[at + i];
    }
    return (patch[at + 7] & 0x80) != 0 ? -y : y;
  }

  final ctrlLen = off(8), diffLen = off(16), newSize = off(24);
  if (ctrlLen < 0 || diffLen < 0 || newSize < 0 || 32 + ctrlLen + diffLen > patch.length) {
    throw const FormatException('Cabeçalho do patch inválido');
  }
  Uint8List bz(int start, int len) =>
      Uint8List.fromList(BZip2Decoder().decodeBytes(Uint8List.sublistView(patch, start, start + len)));
  final ctrl = bz(32, ctrlLen);
  final diff = bz(32 + ctrlLen, diffLen);
  final extra = bz(32 + ctrlLen + diffLen, patch.length - 32 - ctrlLen - diffLen);

  int ctrlOff(int at) {
    var y = ctrl[at + 7] & 0x7f;
    for (var i = 6; i >= 0; i--) {
      y = y * 256 + ctrl[at + i];
    }
    return (ctrl[at + 7] & 0x80) != 0 ? -y : y;
  }

  final out = Uint8List(newSize);
  var newPos = 0, oldPos = 0, cp = 0, dp = 0, ep = 0;
  while (newPos < newSize) {
    if (cp + 24 > ctrl.length) throw const FormatException('Controle do patch incompleto');
    final x = ctrlOff(cp), y = ctrlOff(cp + 8), z = ctrlOff(cp + 16);
    cp += 24;
    if (x < 0 || y < 0 || newPos + x > newSize || dp + x > diff.length) {
      throw const FormatException('Patch corrompido');
    }
    for (var i = 0; i < x; i++) {
      final o = oldPos + i;
      final b = (o >= 0 && o < old.length) ? old[o] : 0;
      out[newPos + i] = (diff[dp + i] + b) & 0xff;
    }
    newPos += x;
    oldPos += x;
    dp += x;
    if (newPos + y > newSize || ep + y > extra.length) throw const FormatException('Patch corrompido');
    out.setRange(newPos, newPos + y, extra, ep);
    newPos += y;
    ep += y;
    oldPos += z;
  }
  return out;
}
