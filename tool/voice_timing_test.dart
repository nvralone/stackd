import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:stackd/clover/kokoro_voice.dart';
import 'package:stackd/clover/phonemizer.dart';
void main() {
  final dir = Platform.environment['KOKORO_DIR'];
  test('timing', () {
    final lib = Platform.environment['SHERPA_LIB']!;
    DynamicLibrary.open('$lib\\onnxruntime.dll');
    so.initBindings(lib);
    final threads = int.parse(Platform.environment['THREADS'] ?? '4');
    final base = kokoroConfig(dir!);
    final sw = Stopwatch()..start();
    final tts = so.OfflineTts(so.OfflineTtsConfig(model: so.OfflineTtsModelConfig(kokoro: base.model.kokoro, numThreads: threads), maxNumSentences: 1));
    final tModel = sw.elapsedMilliseconds;
    final ph = Phonemizer.fromLines(File('$dir/lexicon-us-en.txt').readAsLinesSync());
    final tLex = sw.elapsedMilliseconds - tModel;
    // ignore: avoid_print
    print('model ${tModel}ms, lexicon ${tLex}ms, threads ${Platform.numberOfProcessors}');
    final s = ph.codepoints('No transactions yet. Either you are perfect or you are hiding receipts, so tell me.');
    for (final speed in [1.05]) {
      for (final c in s) {
        final t = Stopwatch()..start();
        final a = tts.generateWithConfig(text: '', config: so.OfflineTtsGenerationConfig(sid: 18, speed: speed, phonemeCodepoints: [c]));
        // ignore: avoid_print
        print('speed $speed: ${t.elapsedMilliseconds}ms -> ${(a.samples.length / a.sampleRate * 1000).round()}ms audio (${c.length} phonemes)');
      }
    }
  }, skip: dir == null, timeout: const Timeout(Duration(minutes: 5)));
}
