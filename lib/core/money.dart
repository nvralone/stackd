/// Integer-cent money helpers. No floating point ever touches a balance.
library;

/// Parses user text like "12", "12.5", "$1,234.56", "-3.10" into cents.
/// Returns null for invalid input or more than 2 decimal places.
int? parseCents(String input) {
  var s = input.trim().replaceAll(',', '').replaceAll('\$', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  var neg = false;
  if (s.startsWith('-')) {
    neg = true;
    s = s.substring(1);
  }
  final m = RegExp(r'^(\d{0,12})(?:\.(\d{0,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = m.group(1)!;
  final frac = m.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  final cents = int.parse(whole.isEmpty ? '0' : whole) * 100 + int.parse(frac.padRight(2, '0'));
  return neg ? -cents : cents;
}

/// Formats cents as "$1,234.56" (negative: "-$1,234.56").
String formatCents(int cents, {String symbol = '\$', bool showPlus = false}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final frac = (abs % 100).toString().padLeft(2, '0');
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final sign = neg ? '-' : (showPlus && cents > 0 ? '+' : '');
  return '$sign$symbol$grouped.$frac';
}

/// Plain decimal string for text fields: 1234.5 -> "1234.50".
String centsToInput(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';

/// Splits [total] into [n] parts that sum exactly to [total]; remainder goes to the first parts.
List<int> splitEvenly(int total, int n) {
  if (n <= 0) return const [];
  final base = total ~/ n;
  final rem = total - base * n;
  return [for (var i = 0; i < n; i++) base + (i < rem ? 1 : 0)];
}

/// Splits [total] proportionally to integer [weights]; exact sum, largest-remainder rounding.
List<int> splitByWeights(int total, List<int> weights) {
  final sum = weights.fold<int>(0, (a, b) => a + b);
  if (sum <= 0) return List.filled(weights.length, 0);
  final parts = [for (final w in weights) total * w ~/ sum];
  final rems = [for (var i = 0; i < weights.length; i++) (total * weights[i]) % sum];
  var left = total - parts.fold<int>(0, (a, b) => a + b);
  final order = List.generate(weights.length, (i) => i)..sort((a, b) => rems[b].compareTo(rems[a]));
  for (final i in order) {
    if (left <= 0) break;
    parts[i]++;
    left--;
  }
  return parts;
}

/// Whole-number percentage (0..100+) without doubles. Returns 0 when [of] <= 0.
int percentOf(int part, int of) => of <= 0 ? 0 : (part * 100) ~/ of;

/// Ceiling integer division for positive divisors.
int ceilDiv(int a, int b) => a <= 0 ? 0 : (a + b - 1) ~/ b;
