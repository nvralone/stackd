// Text -> Kokoro phonemes using the model's own US-English pronunciation dictionary, so no word is
// ever silently skipped: numbers become words, plurals / -ed / -ing are built from the base word,
// stretched words ("nooo") are shrunk, and unknown words (names like "Suno") are sounded out from
// known pieces. Pure Dart; runs inside the voice isolate.

const _ones = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
  'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

/// 0..999,999,999 in words ("1,250" -> "one thousand two hundred fifty").
String numberWords(int n) {
  if (n < 0) return 'minus ${numberWords(-n)}';
  if (n < 20) return _ones[n];
  if (n < 100) return _tens[n ~/ 10] + (n % 10 == 0 ? '' : ' ${_ones[n % 10]}');
  if (n < 1000) return '${_ones[n ~/ 100]} hundred${n % 100 == 0 ? '' : ' ${numberWords(n % 100)}'}';
  if (n < 1000000) return '${numberWords(n ~/ 1000)} thousand${n % 1000 == 0 ? '' : ' ${numberWords(n % 1000)}'}';
  return '${numberWords(n ~/ 1000000)} million${n % 1000000 == 0 ? '' : ' ${numberWords(n % 1000000)}'}';
}

/// Money, percents and plain numbers spelled out the way Clover would say them.
String normalizeText(String t) {
  t = t.replaceAllMapped(RegExp(r'\$([\d,]+)(?:\.(\d\d))?'), (m) {
    final d = int.parse(m[1]!.replaceAll(',', ''));
    final c = m[2] == null ? 0 : int.parse(m[2]!);
    final dollars = '${numberWords(d)} ${d == 1 ? 'dollar' : 'dollars'}';
    return c == 0 ? dollars : '$dollars ${numberWords(c)}';
  });
  t = t.replaceAllMapped(RegExp(r'(\d+)%'), (m) => '${numberWords(int.parse(m[1]!))} percent');
  t = t.replaceAllMapped(RegExp(r'\d[\d,]*'), (m) => numberWords(int.parse(m[0]!.replaceAll(',', ''))));
  return t.replaceAll('&', ' and ').replaceAll(RegExp(r'[-/]'), ' ');
}

class Phonemizer {
  /// word (lower case) -> phonemes, e.g. "bills" -> "bˈɪlz".
  final Map<String, String> lex;
  Phonemizer(this.lex);

  /// Parses lexicon lines: "word p h o n e m e s".
  factory Phonemizer.fromLines(Iterable<String> lines) {
    final m = <String, String>{};
    for (final l in lines) {
      final i = l.indexOf(' ');
      if (i <= 0) continue;
      m.putIfAbsent(l.substring(0, i), () => l.substring(i + 1).replaceAll(' ', ''));
    }
    return Phonemizer(m);
  }

  static const _extra = {
    'heh': 'hˈɛ', 'hehe': 'hˈɛhɛ', 'heheh': 'hˈɛhɛh', 'hahaha': 'hˈɑhɑhɑ', 'zzz': 'zːː', 'mmm': 'mːː', 'nah': 'nˈɑ',
    'ok': 'ˌOkˈA', 'thru': 'θɹˈu',
  };
  static const _letters = {
    'a': 'æ', 'b': 'b', 'c': 'k', 'd': 'd', 'e': 'ɛ', 'f': 'f', 'g': 'ɡ', 'h': 'h', 'i': 'ɪ', 'j': 'ʤ', 'k': 'k', 'l': 'l',
    'm': 'm', 'n': 'n', 'o': 'O', 'p': 'p', 'q': 'k', 'r': 'ɹ', 's': 's', 't': 't', 'u': 'ʌ', 'v': 'v', 'w': 'w', 'x': 'ks',
    'y': 'i', 'z': 'z',
  };

  String? _known(String w) => lex[w] ?? _extra[w];

  /// Phonemes for one word (never null).
  String word(String raw) {
    final w = raw.toLowerCase().replaceAll(RegExp(r"^'+|'+$"), '');
    if (w.isEmpty) return '';
    final k = _known(w);
    if (k != null) return k;
    // possessive / plural
    for (final suf in ["'s", 'es', 's']) {
      if (w.length > suf.length + 1 && w.endsWith(suf)) {
        final stem = _known(w.substring(0, w.length - suf.length));
        if (stem != null) return stem + _plural(stem);
      }
    }
    if (w.endsWith('ing') && w.length > 5) {
      final s = w.substring(0, w.length - 3);
      final stem = _known(s) ?? _known('${s}e') ?? (s.length > 2 && s[s.length - 1] == s[s.length - 2] ? _known(s.substring(0, s.length - 1)) : null);
      if (stem != null) return '$stemɪŋ';
    }
    if (w.endsWith('ed') && w.length > 4) {
      final s = w.substring(0, w.length - 2);
      final stem = _known(s) ?? _known('${s}e');
      if (stem != null) return stem + (RegExp(r'[td]$').hasMatch(stem) ? 'ɪd' : (RegExp(r'[pkfsʃθ]$').hasMatch(stem) || stem.endsWith('ʧ') ? 't' : 'd'));
    }
    // stretched words: "nooo" -> "no", "sooo" -> "so"
    final squeezed = w.replaceAllMapped(RegExp(r'(.)\1{2,}'), (m) => m[1]!);
    if (squeezed != w) {
      final k2 = _known(squeezed) ?? _known(w.replaceAllMapped(RegExp(r'(.)\1{2,}'), (m) => '${m[1]}${m[1]}'));
      if (k2 != null) return k2;
    }
    return _soundOut(w);
  }

  static String _plural(String stem) {
    if (RegExp(r'(s|z|ʃ|ʒ|ʧ|ʤ)$').hasMatch(stem)) return 'ɪz';
    if (RegExp(r'[ptkfθ]$').hasMatch(stem)) return 's';
    return 'z';
  }

  /// Unknown word: longest known pieces first (at least 2 letters), single letters as a last resort.
  String _soundOut(String w) {
    final out = StringBuffer();
    var i = 0;
    while (i < w.length) {
      var found = false;
      for (var j = w.length < i + 10 ? w.length : i + 10; j >= i + 2; j--) {
        final k = lex[w.substring(i, j)];
        if (k != null) {
          out.write(out.isEmpty ? k : k.replaceAll('ˈ', 'ˌ'));
          i = j;
          found = true;
          break;
        }
      }
      if (!found) {
        out.write(_letters[w[i]] ?? '');
        i++;
      }
    }
    return out.toString();
  }

  /// Phoneme codepoints, one list per sentence (what the model takes instead of text).
  List<List<int>> codepoints(String text) {
    final norm = normalizeText(text);
    final sentences = <List<int>>[];
    final cur = StringBuffer();
    void flush() {
      final s = cur.toString().trim();
      if (s.isNotEmpty) sentences.add(s.runes.toList());
      cur.clear();
    }

    for (final m in RegExp(r"[A-Za-z']+|[.!?]+|[,;:…—]").allMatches(norm)) {
      final tok = m[0]!;
      if (RegExp(r'^[.!?]+$').hasMatch(tok)) {
        cur.write(tok.contains('?') ? '?' : (tok.contains('!') ? '!' : '.'));
        flush();
      } else if (RegExp(r'^[,;:…—]$').hasMatch(tok)) {
        cur.write(tok == '—' || tok == '…' ? tok : ',');
      } else {
        final p = word(tok);
        if (p.isEmpty) continue;
        if (cur.isNotEmpty) cur.write(' ');
        cur.write(p);
      }
    }
    flush();
    return sentences;
  }
}
