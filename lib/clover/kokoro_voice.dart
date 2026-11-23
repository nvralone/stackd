// Clover's character voice: the free, offline Kokoro-82M speech model (Apache-2.0), run on the device
// with sherpa-onnx. Downloaded once when the user turns it on (no server, no account, no paid API).
// Clover's sound = a playful Kokoro voice, raised in pitch by resampling, with delivery changes for
// yelling / whispering. It is a general speech model shaped toward a character - not a voice actor.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'phonemizer.dart';

const kokoroUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2';
const kokoroDownloadBytes = 132353410;
const _folder = 'kokoro-int8-multi-lang-v1_0';

/// Only what English speech needs is kept after extracting (~145 MB on disk).
bool _keep(String name) {
  final n = name.startsWith('$_folder/') ? name.substring(_folder.length + 1) : name;
  return n == 'model.int8.onnx' || n == 'voices.bin' || n == 'tokens.txt' || n == 'lexicon-us-en.txt' || n == 'LICENSE';
}

/// Clover's voice: Kokoro speaker "am_puck" (id from the model's own table). Only this one is tuned for him.
const cloverSid = 18;

so.OfflineTtsConfig kokoroConfig(String dir) => so.OfflineTtsConfig(
      model: so.OfflineTtsModelConfig(
        kokoro: so.OfflineTtsKokoroModelConfig(
          model: '$dir/model.int8.onnx',
          voices: '$dir/voices.bin',
          tokens: '$dir/tokens.txt',
          lexicon: '$dir/lexicon-us-en.txt',
        ),
        numThreads: Platform.numberOfProcessors >= 6 ? 4 : 2,
      ),
      maxNumSentences: 1,
    );

/// How a line should be delivered, read from the text itself.
enum Tone { normal, yell, whisper }

/// Speech text + delivery. "*whispers*" style cues are removed from what's spoken; mostly ALL CAPS = yelling.
({String text, Tone tone}) deliver(String line) {
  final whisper = RegExp(r'\*whisper', caseSensitive: false).hasMatch(line);
  final t = line.replaceAll(RegExp(r'\*[^*]*\*'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final upper = t.replaceAll(RegExp('[^A-Z]'), '').length;
  final lower = t.replaceAll(RegExp('[^a-z]'), '').length;
  return (text: t, tone: whisper ? Tone.whisper : (upper > lower ? Tone.yell : Tone.normal));
}
/// Mono float samples -> 16-bit WAV. [pitch] > 1 raises pitch (and speed) by declaring a higher sample rate.
Uint8List wavBytes(Float32List samples, int sampleRate, {double pitch = 1.0, double volume = 1.0}) {
  final rate = (sampleRate * pitch).round();
  final n = samples.length;
  final d = ByteData(44 + n * 2);
  void str(int o, String v) {
    for (var i = 0; i < v.length; i++) {
      d.setUint8(o + i, v.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  d.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, rate, Endian.little);
  d.setUint32(28, rate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  str(36, 'data');
  d.setUint32(40, n * 2, Endian.little);
  final fade = (sampleRate * 0.01).round();
  for (var i = 0; i < n; i++) {
    var v = samples[i] * volume;
    if (i < fade) v *= i / fade;
    if (i > n - fade) v *= (n - i) / fade;
    d.setInt16(44 + i * 2, (v.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return d.buffer.asUint8List();
}

/// Settings for one spoken line.
class VoiceStyle {
  final int sid;
  final double pitch, speed;
  const VoiceStyle({this.sid = 18, this.pitch = 1.18, this.speed = 1.05});
}

/// Downloads, unpacks and runs the Kokoro model in a background isolate so the UI never stutters.
class KokoroVoice {
  KokoroVoice._();
  static final instance = KokoroVoice._();

  SendPort? _worker;
  Future<void>? _starting;

  static Future<Directory> _dir() async => Directory('${(await getApplicationSupportDirectory()).path}/voice/$_folder');

  Future<bool> get installed async {
    final d = await _dir();
    return File('${d.path}/model.int8.onnx').existsSync() && File('${d.path}/voices.bin').existsSync() && File('${d.path}/.complete').existsSync();
  }

  /// Downloads (~132 MB) and unpacks the model. [progress] gets 0..1 while downloading.
  Future<void> install({void Function(double)? progress}) async {
    final root = Directory('${(await getApplicationSupportDirectory()).path}/voice');
    await root.create(recursive: true);
    final archive = File('${root.path}/kokoro.tar.bz2');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(kokoroUrl));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Download failed (${res.statusCode})');
      final total = res.contentLength > 0 ? res.contentLength : kokoroDownloadBytes;
      final sink = archive.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        progress?.call(got / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    // Unpack in the background: bz2 is slow and the archive is big.
    await Isolate.run(() => unpackKokoro(archive.path, root.path));
    await archive.delete();
    await File('${root.path}/$_folder/.complete').writeAsString('ok');
  }

  /// Unpacks the downloaded .tar.bz2 into [outDir], keeping only the English files.
  static void unpackKokoro(String archivePath, String outDir) {
    final tarPath = '$archivePath.tar';
    final input = InputFileStream(archivePath);
    final output = OutputFileStream(tarPath);
    BZip2Decoder().decodeStream(input, output);
    input.closeSync();
    output.closeSync();
    final tarIn = InputFileStream(tarPath);
    final tar = TarDecoder().decodeStream(tarIn);
    for (final f in tar.files) {
      if (!f.isFile || !_keep(f.name)) continue;
      final out = OutputFileStream('$outDir/${f.name}');
      f.writeContent(out);
      out.closeSync();
    }
    tarIn.closeSync();
    File(tarPath).deleteSync();
  }

  Future<void> uninstall() async {
    _worker?.send(null);
    _worker = null;
    final d = await _dir();
    if (d.existsSync()) await d.delete(recursive: true);
  }

  Future<void> _start() async {
    final dir = (await _dir()).path;
    final ready = ReceivePort();
    await Isolate.spawn(_workerMain, (ready.sendPort, dir));
    _worker = await ready.first as SendPort;
  }

  /// Speaks [line] as a stream of WAV clips, one per sentence, so playback can start after the first
  /// sentence instead of waiting for the whole line. Errors arrive as stream errors.
  Stream<Uint8List> speak(String line, VoiceStyle style) async* {
    if (_worker == null) {
      _starting ??= _start();
      try {
        await _starting;
      } finally {
        _starting = null;
      }
    }
    final d = deliver(line);
    final (pitch, speed, volume) = switch (d.tone) {
      Tone.yell => (style.pitch * 1.06, style.speed * 1.12, 1.0),
      Tone.whisper => (style.pitch * 0.97, style.speed * 0.88, 0.45),
      Tone.normal => (style.pitch, style.speed, 0.9),
    };
    final reply = ReceivePort();
    // Pitch-up by resampling also speeds speech up, so generate it slower to compensate.
    _worker!.send((reply.sendPort, d.text, style.sid, speed / pitch, pitch, volume));
    await for (final r in reply) {
      if (r == true) break; // done
      if (r is String) {
        reply.close();
        throw Exception(r);
      }
      yield r as Uint8List;
    }
    reply.close();
  }

  static void _workerMain((SendPort, String) args) {
    final (ready, dir) = args;
    final inbox = ReceivePort();
    so.OfflineTts? tts;
    Phonemizer? ph;
    String? error;
    try {
      so.initBindings();
      tts = so.OfflineTts(kokoroConfig(dir));
      ph = Phonemizer.fromLines(File('$dir/lexicon-us-en.txt').readAsLinesSync());
    } catch (e) {
      error = 'Voice failed to load: $e';
    }
    ready.send(inbox.sendPort);
    inbox.listen((msg) {
      if (msg == null) {
        tts?.free();
        inbox.close();
        return;
      }
      final (reply, text, sid, speed, pitch, volume) = msg as (SendPort, String, int, double, double, double);
      if (tts == null || ph == null) return reply.send(error ?? 'Voice not loaded');
      try {
        for (final sentence in ph.codepoints(text)) {
          final a = tts.generateWithConfig(
              text: '', config: so.OfflineTtsGenerationConfig(sid: sid, speed: speed, phonemeCodepoints: [sentence]));
          if (a.samples.isNotEmpty) reply.send(wavBytes(a.samples, a.sampleRate, pitch: pitch, volume: volume));
        }
        reply.send(true);
      } catch (e) {
        reply.send('Voice error: $e');
      }
    });
  }
}

/// Joins WAV clips made by [wavBytes] (same format) into one file, for caching a whole line.
Uint8List joinWavs(List<Uint8List> clips) {
  if (clips.length == 1) return clips.single;
  final pcm = clips.fold<int>(0, (s, c) => s + c.length - 44);
  final out = Uint8List(44 + pcm)..setRange(0, 44, clips.first);
  final d = ByteData.sublistView(out);
  d.setUint32(4, 36 + pcm, Endian.little);
  d.setUint32(40, pcm, Endian.little);
  var o = 44;
  for (final c in clips) {
    out.setRange(o, o + c.length - 44, c, 44);
    o += c.length - 44;
  }
  return out;
}
/// Generates speech from phonemes (so every word is pronounced, even ones the model's dictionary lacks).
so.GeneratedAudio synth(so.OfflineTts tts, Phonemizer ph, String text, int sid, double speed) {
  final cps = ph.codepoints(text);
  if (cps.isEmpty) return so.GeneratedAudio(samples: Float32List(0), sampleRate: tts.sampleRate);
  return tts.generateWithConfig(text: '', config: so.OfflineTtsGenerationConfig(sid: sid, speed: speed, phonemeCodepoints: cps));
}