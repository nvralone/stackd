// Times the in-app unpacker on the real downloaded archive. Skipped unless KOKORO_ARCHIVE is set.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/clover/kokoro_voice.dart';

void main() {
  final a = Platform.environment['KOKORO_ARCHIVE'];
  test('unpack', () {
    final out = Platform.environment['UNPACK_OUT']!;
    final sw = Stopwatch()..start();
    KokoroVoice.unpackKokoro(a!, out);
    // ignore: avoid_print
    print('unpacked in ${sw.elapsed.inSeconds}s');
    for (final f in Directory(out).listSync(recursive: true).whereType<File>()) {
      // ignore: avoid_print
      print('${f.path.substring(out.length)} ${f.lengthSync()}');
    }
  }, skip: a == null ? 'set KOKORO_ARCHIVE' : false, timeout: const Timeout(Duration(minutes: 15)));
}
