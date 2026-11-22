import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/core/money.dart';

void main() {
  group('currency precision', () {
    test('parses without floating point error', () {
      expect(parseCents('0.1'), 10);
      expect(parseCents('0.2'), 20);
      expect(parseCents('0.1')! + parseCents('0.2')!, 30); // 0.1 + 0.2 == 0.3 exactly
      expect(parseCents('\$1,234.56'), 123456);
      expect(parseCents('19.99'), 1999);
      expect(parseCents('-3.5'), -350);
      expect(parseCents('.5'), 50);
      expect(parseCents('12.345'), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents(''), isNull);
    });

    test('formats', () {
      expect(formatCents(123456), '\$1,234.56');
      expect(formatCents(-5), '-\$0.05');
      expect(formatCents(100000000), '\$1,000,000.00');
      expect(formatCents(250, showPlus: true), '+\$2.50');
    });

    test('splits are exact', () {
      expect(splitEvenly(1000, 3), [334, 333, 333]);
      expect(splitEvenly(1000, 3).reduce((a, b) => a + b), 1000);
      final w = splitByWeights(7900, [1, 1, 1]);
      expect(w.reduce((a, b) => a + b), 7900);
      expect(splitByWeights(100, [0, 0]), [0, 0]);
    });

    test('many small amounts sum exactly', () {
      var total = 0;
      for (var i = 0; i < 10000; i++) {
        total += parseCents('0.01')!;
      }
      expect(total, 10000);
    });
  });

  group('weekly period boundaries', () {
    test('week start respects custom start day', () {
      final wed = day(2026, 11, 18); // Wednesday
      expect(weekStartOf(wed, 1), day(2026, 11, 16)); // Monday start
      expect(weekStartOf(wed, 7), day(2026, 11, 15)); // Sunday start
      expect(weekStartOf(wed, 3), wed); // Wednesday start = same day
      expect(weekStartOf(wed, 5), day(2026, 11, 13)); // Friday start
    });

    test('period is half-open across month/year edges', () {
      final p = periodOf(day(2026, 12, 31), 'weekly', 1);
      expect(p.start, day(2026, 12, 28));
      expect(p.end, day(2027, 1, 4));
      final m = periodOf(day(2026, 2, 14), 'monthly', 1);
      expect(m.start, day(2026, 2, 1));
      expect(m.end, day(2026, 3, 1));
    });

    test('monthly schedules clamp to month end', () {
      final jan31 = day(2026, 1, 31);
      expect(nthOccurrence(jan31, 'monthly', 1), day(2026, 2, 28));
      expect(nthOccurrence(jan31, 'monthly', 2), day(2026, 3, 31));
      expect(nthOccurrence(day(2026, 1, 1), 'biweekly', 2), day(2026, 1, 29));
    });

    test('next occurrence', () {
      expect(nextOccurrence(day(2026, 11, 6), 'weekly', day(2026, 11, 18)), day(2026, 11, 20));
      expect(nextOccurrence(day(2026, 11, 20), 'weekly', day(2026, 11, 18)), day(2026, 11, 20));
      expect(nextOccurrence(day(2026, 11, 1), 'once', day(2026, 11, 18)), isNull);
    });
  });
}
