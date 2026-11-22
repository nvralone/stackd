// Clover's free, local voice.
// - "talk"  : Clover actually says the line with the device voice, pitched up into a goofy cartoon range,
//             with a quick chirp in front. Default.
// - "babble": cartoon gibberish synthesized per syllable (vowel formants + raspy pulse), Animal-Crossing style.
// No network, no paid service.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'moods.dart';

const _rate = 22050;

/// Vowel formants (F1, F2) in Hz, raised slightly for a small character.
const _formants = {
  'a': (850.0, 1450.0),
  'e': (550.0, 2100.0),
  'i': (350.0, 2600.0),
  'o': (550.0, 1000.0),
  'u': (400.0, 1100.0),
};

/// Two-pole resonator (biquad band-pass) state.
class _Reso {
  double b0 = 0, a1 = 0, a2 = 0, y1 = 0, y2 = 0, x1 = 0, x2 = 0;
  void tune(double f, double q) {
    final w = 2 * pi * f / _rate, alpha = sin(w) / (2 * q), a0 = 1 + alpha;
    b0 = alpha / a0;
    a1 = -2 * cos(w) / a0;
    a2 = (1 - alpha) / a0;
  }

  double run(double x) {
    final y = b0 * x - b0 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    return y;
  }
}

/// Gibberish voice: one short syllable per letter (max ~28), pitch follows the mood.
/// Pure + deterministic for a given text, so it is unit-testable.
Uint8List synthBabble(String text, double pitch, {int seed = 7}) {
  final rng = Random(seed ^ text.hashCode);
  final letters = text.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  final chars = letters.isEmpty ? 'hey' : (letters.length > 28 ? letters.substring(0, 28) : letters);
  final question = text.trim().endsWith('?');
  final shout = text.replaceAll(RegExp('[^A-Z]'), '').length > text.replaceAll(RegExp('[^a-z]'), '').length;
  final out = <double>[];
  final f1 = _Reso(), f2 = _Reso();
  var phase = 0.0;
  final base = 300.0 * pitch * (shout ? 1.12 : 1.0);
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    final vowel = 'aeiou'.contains(c) ? c : 'aeiou'[(c.codeUnitAt(0) * 7) % 5];
    final (fa, fb) = _formants[vowel]!;
    f1.tune(fa * (0.95 + rng.nextDouble() * 0.1), 6);
    f2.tune(fb * (0.95 + rng.nextDouble() * 0.1), 9);
    final progress = i / chars.length;
    final contour = question ? 1 + progress * 0.35 : 1.08 - progress * 0.15; // sing-song shape
    final f0 = base * contour * (0.88 + rng.nextDouble() * 0.28);
    final len = (_rate * (0.045 + rng.nextDouble() * 0.025)).toInt();
    final consonant = !'aeiou'.contains(c);
    for (var n = 0; n < len; n++) {
      final t = n / len;
      final env = t < 0.12 ? t / 0.12 : (t > 0.75 ? (1 - t) / 0.25 : 1.0);
      final vib = 1 + 0.03 * sin(2 * pi * 7 * n / _rate);
      phase += f0 * vib / _rate;
      if (phase >= 1) phase -= 1;
      final pulse = 1 - 2 * phase; // bright sawtooth = cartoonish buzz
      final rasp = (rng.nextDouble() * 2 - 1) * 0.18; // slight gravel
      var src = pulse + rasp;
      if (consonant && t < 0.2) src = (rng.nextDouble() * 2 - 1) * 1.2; // "t/k/s" click at syllable start
      final v = f1.run(src) * 1.0 + f2.run(src) * 0.7;
      out.add(v * env);
    }
    if (rng.nextInt(5) == 0) out.addAll(List.filled((_rate * 0.03).toInt(), 0)); // natural micro-pauses
  }
  out.addAll(List.filled((_rate * 0.05).toInt(), 0));
  final peak = out.fold<double>(0.0001, (m, v) => max(m, v.abs()));
  final samples = [for (final v in out) (v / peak * 0.85 * 32767).round().clamp(-32768, 32767)];
  return _wav(samples);
}

/// Tiny rising "hm!" chirp played before Clover talks.
Uint8List synthChirp(double pitch) {
  final s = <int>[];
  final n = (_rate * 0.09).toInt();
  var ph = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / n;
    ph += (500 + 700 * t) * pitch / _rate;
    s.add((sin(2 * pi * ph) * sin(pi * t) * 0.5 * 32767).round());
  }
  return _wav(s);
}

Uint8List _wav(List<int> samples) {
  final d = ByteData(44 + samples.length * 2);
  void str(int o, String v) {
    for (var i = 0; i < v.length; i++) {
      d.setUint8(o + i, v.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  d.setUint32(4, 36 + samples.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, _rate, Endian.little);
  d.setUint32(28, _rate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  str(36, 'data');
  d.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    d.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return d.buffer.asUint8List();
}

/// TTS reads ALL-CAPS words as letters on some engines; speak them as normal words.
String speakable(String text) => text.replaceAllMapped(
    RegExp(r"\b[A-Z][A-Z']{2,}\b"), (m) => m[0]!.toLowerCase()).replaceAll('\$', ' dollars ').replaceAll(RegExp(r'\s+'), ' ');

/// Device-voice pitch for a mood: always high and cartoony (TTS range is 0.5..2.0).
double ttsPitch(CloverMood mood) => (1.45 + (mood.pitch - 1) * 0.6).clamp(1.15, 2.0);

class CloverVoice {
  final _player = AudioPlayer();
  final _tts = FlutterTts();
  bool _ttsReady = false;
  void Function(bool talking)? onTalking;

  Future<void> _play(Uint8List wav, int volume, String name) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/clover_$name.wav');
    await f.writeAsBytes(wav);
    await _player.stop();
    await _player.setVolume(volume / 100);
    await _player.play(DeviceFileSource(f.path));
  }

  Future<void> _initTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    _tts.setStartHandler(() => onTalking?.call(true));
    _tts.setCompletionHandler(() => onTalking?.call(false));
    _tts.setCancelHandler(() => onTalking?.call(false));
    try {
      // Prefer a lighter voice: it pitches up into a better cartoon range.
      final voices = List<Map>.from((await _tts.getVoices) as List? ?? const []);
      const prefer = ['Aria', 'Jenny', 'Ana', 'Zira', 'Samantha', 'Ava', 'Karen', 'female'];
      for (final p in prefer) {
        final v = voices.where((v) => '${v['name']}'.contains(p) && '${v['locale']}'.toLowerCase().startsWith('en')).firstOrNull;
        if (v != null) {
          await _tts.setVoice({'name': '${v['name']}', 'locale': '${v['locale']}'});
          break;
        }
      }
    } catch (_) {}
  }

  /// Gibberish reaction.
  Future<void> babble(String text, CloverMood mood, {required int volume}) async {
    try {
      onTalking?.call(true);
      await _play(synthBabble(text, mood.pitch), volume, 'babble');
      final ms = 60 * text.replaceAll(RegExp('[^A-Za-z]'), '').length.clamp(3, 28);
      Future.delayed(Duration(milliseconds: ms), () => onTalking?.call(false));
    } catch (_) {
      onTalking?.call(false); // audio unavailable: subtitles still show
    }
  }

  /// Clover says the actual words in a pitched-up goofy voice.
  Future<void> talk(String text, CloverMood mood, {required int volume, bool chirp = true}) async {
    try {
      await _initTts();
      await _tts.stop();
      if (chirp) {
        await _play(synthChirp(mood.pitch), volume, 'chirp');
        await Future<void>.delayed(const Duration(milliseconds: 110));
      }
      await _tts.setVolume(volume / 100);
      await _tts.setPitch(ttsPitch(mood));
      await _tts.setSpeechRate(Platform.isIOS ? 0.52 : 0.58);
      await _tts.speak(speakable(text));
    } catch (_) {
      await babble(text, mood, volume: volume); // no TTS voice: fall back to gibberish
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      await _tts.stop();
    } catch (_) {}
    onTalking?.call(false);
  }
}
