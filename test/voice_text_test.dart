import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/clover/kokoro_voice.dart';
import 'package:stackd/clover/phonemizer.dart';

final lexicon = [
  'bills b ˈ ɪ l z',
  'nugget n ˈ ʌ ɡ ə t',
  'no n ˈ O',
  'sun s ˈ ʌ n',
  'pay p ˈ A',
  'okay ˌ O k ˈ A',
  'dollars d ˈ ɑ l ə ɹ z',
  'dollar d ˈ ɑ l ə ɹ',
  'twenty t w ˈ ɛ n t i',
  'five f ˈ I v',
  'nine n ˈ I n',
  'cents s ˈ ɛ n t s',
  'percent p ə ɹ s ˈ ɛ n t',
  'stack s t ˈ æ k',
  'watch w ˈ ɑ ʧ',
];

void main() {
  final ph = Phonemizer.fromLines(lexicon);

  test('numbers and money become words', () {
    expect(numberWords(295), 'two hundred ninety five');
    expect(numberWords(1250), 'one thousand two hundred fifty');
    expect(normalizeText('\$25.09'), 'twenty five dollars nine');
    expect(normalizeText('\$1.00'), 'one dollar');
    expect(normalizeText('50%'), 'fifty percent');
  });

  test('known words use the dictionary', () {
    expect(ph.word('Bills'), 'bˈɪlz');
    expect(ph.word('okay'), 'ˌOkˈA');
  });

  test('plurals, -ing and stretched words are built from known words', () {
    expect(ph.word('nuggets'), 'nˈʌɡətz'.replaceAll('tz', 'ts')); // voiceless t -> s
    expect(ph.word('watches'), 'wˈɑʧɪz');
    expect(ph.word('stacking'), 'stˈækɪŋ');
    expect(ph.word('Nooo'), 'nˈO');
    expect(ph.word('heh'), 'hˈɛ');
  });

  test('unknown words are sounded out, never dropped', () {
    final suno = ph.word('Suno');
    expect(suno, isNotEmpty);
    expect(suno, startsWith('sˈʌn')); // "sun" + "o"
    expect(ph.word('xq'), isNotEmpty);
  });

  test('sentences split on . ! ? and keep punctuation', () {
    final s = ph.codepoints('Pay bills! No nuggets, okay?');
    expect(s.length, 2);
    expect(String.fromCharCodes(s[0]), 'pˈA bˈɪlz!');
    expect(String.fromCharCodes(s[1]), 'nˈO nˈʌɡəts, ˌOkˈA?');
  });

  test('delivery: whisper cue removed, caps = yelling', () {
    final w = deliver('*whispers* psst. Insurance is due.');
    expect(w.tone, Tone.whisper);
    expect(w.text, 'psst. Insurance is due.');
    expect(deliver('WHO AUTHORIZED THIS?!').tone, Tone.yell);
    expect(deliver('Bills first, okay?').tone, Tone.normal);
  });

  test('wav: pitch raises the declared sample rate; clips join into one file', () {
    final a = wavBytes(Float32List.fromList(List.filled(240, 0.5)), 24000, pitch: 1.2);
    final d = ByteData.sublistView(a);
    expect(String.fromCharCodes(a.sublist(0, 4)), 'RIFF');
    expect(d.getUint32(24, Endian.little), 28800);
    final j = joinWavs([a, a]);
    expect(j.length, 44 + 2 * 480);
    expect(ByteData.sublistView(j).getUint32(40, Endian.little), 960);
  });
}
