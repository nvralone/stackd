import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:stackd/clover/kokoro_voice.dart';
import 'package:stackd/clover/phonemizer.dart';
void main() {
  final dir = Platform.environment['KOKORO_DIR'];
  test('line', () {
    final lib = Platform.environment['SHERPA_LIB']!;
    DynamicLibrary.open('$lib\\onnxruntime.dll');
    so.initBindings(lib);
    final tts = so.OfflineTts(kokoroConfig(dir!));
    final ph = Phonemizer.fromLines(File('$dir/lexicon-us-en.txt').readAsLinesSync());
    for (final line in [
      "You've got \$25.45 free until Nov 27. That's \$6.36 a day. Spend it like you mean it.",
      "\$6.36 a day. Not a fortune, but it's YOUR fortune.",
      'PAYDAY! Okay okay, bills first. Then we party. A little.',
    ]) {
      for (final s in ph.codepoints(deliver(line).text)) {
        final sw = Stopwatch()..start();
        try {
          final a = tts.generateWithConfig(text: '', config: so.OfflineTtsGenerationConfig(sid: 18, speed: 1.05 / 1.3, phonemeCodepoints: [s]));
          // ignore: avoid_print
          print('OK ${sw.elapsedMilliseconds}ms ${a.samples.length} samples: ${String.fromCharCodes(s)}');
        } catch (e) {
          // ignore: avoid_print
          print('FAIL ${String.fromCharCodes(s)} -> $e');
        }
      }
    }
  }, skip: dir == null, timeout: const Timeout(Duration(minutes: 5)));
}
