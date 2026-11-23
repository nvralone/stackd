// Clover's character voice: the free, offline Kokoro-82M speech model (Apache-2.0), run on the device
// with sherpa-onnx. Downloaded once when the user turns it on (no server, no account, no paid API).
// Clover's sound = a playful Kokoro voice, raised in pitch by resampling, with delivery changes for
// yelling / whispering. It is a general speech model shaped toward a character - not a voice actor.
import 'dart:async';
import 'dart:collection';
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
        // measured: 6 threads is fastest on a 12-core PC; more adds overhead
        numThreads: Platform.numberOfProcessors >= 8 ? 6 : (Platform.numberOfProcessors >= 4 ? 4 : 2),
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

  Future<void> _ensureStarted() async {
    if (_worker != null) return;
    _starting ??= _start();
    try {
      await _starting;
    } finally {
      _starting = null;
    }
  }

  /// Loads the model in the background (takes a few seconds) so the first line isn't late.
  Future<void> warmUp() async {
    if (_worker == null && await installed) await _ensureStarted();
  }

  // The worker does one small job at a time (split a line into sentences, or make one sentence).
  // Lines someone is waiting to hear go in front of lines being made ahead of time, so a background
  // job can never hold up what you just tapped by more than one sentence.
  final _urgent = Queue<_Job>(), _background = Queue<_Job>();
  bool _busy = false;

  /// Same sentence already queued or being made (e.g. the Home line being prepared when you tap
  /// replay): reuse that job instead of making it twice, and move it to the front if you're waiting.
  final _byKey = <String, _Job>{};

  Future<Object?> _run(Object msg, {required bool urgent, String? key}) {
    final existing = key == null ? null : _byKey[key];
    if (existing != null) {
      if (urgent && _background.remove(existing)) _urgent.add(existing);
      return existing.done.future;
    }
    final j = _Job(msg);
    if (key != null) {
      _byKey[key] = j;
      j.done.future.whenComplete(() => _byKey.remove(key));
    }
    (urgent ? _urgent : _background).add(j);
    _pump();
    return j.done.future;
  }

  Future<void> _pump() async {
    if (_busy || _worker == null) return;
    final j = _urgent.isNotEmpty ? _urgent.removeFirst() : (_background.isNotEmpty ? _background.removeFirst() : null);
    if (j == null) return;
    _busy = true;
    final port = ReceivePort();
    _worker!.send((port.sendPort, j.msg));
    final r = await port.first;
    port.close();
    _busy = false;
    j.done.complete(r);
    _pump();
  }

  /// Drops queued sentences of lines nobody is waiting for anymore (a newer line was tapped).
  void cancelUrgent() {
    while (_urgent.isNotEmpty) {
      _urgent.removeFirst().done.complete(null);
    }
  }

  /// Speaks [line] as a stream of WAV clips, one per sentence, so playback can start after the first
  /// sentence instead of waiting for the whole line. All sentences are queued at once, so the next one
  /// is being made while the current one plays. [urgent]: someone is waiting to hear it.
  /// Errors arrive as stream errors; a cancelled line just ends.
  Stream<Uint8List> speak(String line, VoiceStyle style, {bool urgent = true}) async* {
    await _ensureStarted();
    final d = deliver(line);
    final (pitch, speed, volume) = switch (d.tone) {
      Tone.yell => (style.pitch * 1.06, style.speed * 1.12, 1.0),
      Tone.whisper => (style.pitch * 0.97, style.speed * 0.88, 0.45),
      Tone.normal => (style.pitch, style.speed, 0.9),
    };
    final split = await _run(('split', d.text), urgent: urgent, key: 'split|${d.text}');
    if (split == null) return;
    if (split is String) throw Exception(split);
    // A long first sentence is split at its first comma so Clover starts talking sooner.
    final sentences = [for (final s in split as List) s as List<int>];
    if (sentences.isNotEmpty && sentences.first.length > 30) {
      final comma = sentences.first.indexOf(44); // ','
      if (comma > 8 && comma < sentences.first.length - 8) {
        final first = sentences.removeAt(0);
        sentences.insertAll(0, [first.sublist(0, comma + 1), first.sublist(comma + 1).skipWhile((c) => c == 32).toList()]);
      }
    }
    // Pitch-up by resampling also speeds speech up, so generate it slower to compensate.
    final jobs = [
      for (final cps in sentences)
        _run(('gen', cps, style.sid, speed / pitch, pitch, volume),
            urgent: urgent, key: '${style.sid}|${(speed / pitch).toStringAsFixed(3)}|${pitch.toStringAsFixed(3)}|$volume|${cps.join(',')}'),
    ];
    for (final job in jobs) {
      final r = await job;
      if (r == null) return;
      if (r is String) throw Exception(r);
      if ((r as Uint8List).length > 44) yield r;
    }
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
      final (reply, job) = msg as (SendPort, Object);
      if (tts == null || ph == null) return reply.send(error ?? 'Voice not loaded');
      try {
        switch (job) {
          case ('split', String text):
            reply.send(ph.codepoints(text));
          case ('gen', List<int> cps, int sid, double speed, double pitch, double volume):
            final a = tts.generateWithConfig(text: '', config: so.OfflineTtsGenerationConfig(sid: sid, speed: speed, phonemeCodepoints: [cps]));
            reply.send(wavBytes(a.samples, a.sampleRate, pitch: pitch, volume: volume));
          default:
            reply.send('Voice error: unknown job');
        }
      } catch (e) {
        reply.send('Voice error: $e');
      }
    });
  }
}

class _Job {
  final Object msg;
  final done = Completer<Object?>();
  _Job(this.msg);
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