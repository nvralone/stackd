// Generates Clover voice samples with the offline Kokoro model, for picking a voice.
//   $env:KOKORO_DIR='...\kokoro-int8-multi-lang-v1_0'; $env:SHERPA_LIB='...\sherpa_onnx_windows-2.0.3\windows\x64'
//   $env:VOICE_OUT='...\out'; flutter test tool/voice_try_test.dart
// Skipped unless KOKORO_DIR is set.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:stackd/clover/kokoro_voice.dart';
import 'package:stackd/clover/phonemizer.dart';

void main() {
  final dir = Platform.environment['KOKORO_DIR'];
  test('voice samples', () {
    final lib = Platform.environment['SHERPA_LIB']!;
    DynamicLibrary.open('$lib\\onnxruntime.dll'); // Windows ships an older onnxruntime in System32; load ours first
    so.initBindings(lib);
    final tts = so.OfflineTts(kokoroConfig(dir!));
    final ph = Phonemizer.fromLines(File('$dir/lexicon-us-en.txt').readAsLinesSync());
    final out = Platform.environment['VOICE_OUT']!;
    Directory(out).createSync(recursive: true);
    // ignore: avoid_print
    print('speakers: ${tts.numSpeakers}');
    const line = "PAYDAY! \$295.00 just landed. Heh heh. Nooo nuggets this week, okay? Suno is due, damn it.";
    for (final sid in [18]) {
      for (final pitch in [1.0, 1.18]) {
        final sw = Stopwatch()..start();
        final a = synth(tts, ph, deliver(line).text, sid, 1.05 / pitch);
        // ignore: avoid_print
        print('sid $sid pitch $pitch: ${sw.elapsedMilliseconds} ms for ${(a.samples.length / a.sampleRate).toStringAsFixed(1)} s audio');
        final w = wavBytes(a.samples, a.sampleRate, pitch: pitch);
        File('$out/sid${sid}_p${(pitch * 100).round()}.wav').writeAsBytesSync(w);
      }
    }
    tts.free();
  }, skip: dir == null ? 'set KOKORO_DIR' : false, timeout: const Timeout(Duration(minutes: 10)));
}
