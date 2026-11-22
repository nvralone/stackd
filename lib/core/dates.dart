/// Date-only helpers. Dates are UTC midnight DateTimes so DST never shifts a day.
library;

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

DateTime dateOnly(DateTime t) => DateTime.utc(t.year, t.month, t.day);

DateTime today([DateTime? now]) => dateOnly(now ?? DateTime.now());

DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

int daysBetween(DateTime a, DateTime b) => dateOnly(b).difference(dateOnly(a)).inDays;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String s) {
  final p = s.substring(0, 10).split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Adds [months] keeping [anchorDay] where possible (Jan 31 + 1 month = Feb 28/29).
DateTime addMonths(DateTime d, int months, {int? anchorDay}) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12, m = total % 12 + 1;
  final last = DateTime.utc(y, m + 1, 0).day;
  final want = anchorDay ?? d.day;
  return DateTime.utc(y, m, want > last ? last : want);
}

/// Start of the week containing [d]; [weekStart] is ISO weekday 1 (Mon) .. 7 (Sun).
DateTime weekStartOf(DateTime d, int weekStart) {
  final back = (d.weekday - weekStart + 7) % 7;
  return addDays(dateOnly(d), -back);
}

DateTime monthStartOf(DateTime d) => DateTime.utc(d.year, d.month, 1);

/// Half-open period [start, end) for a budget period type.
({DateTime start, DateTime end}) periodOf(DateTime d, String period, int weekStart) {
  if (period == 'monthly') {
    final s = monthStartOf(d);
    return (start: s, end: addMonths(s, 1));
  }
  final s = weekStartOf(d, weekStart);
  return (start: s, end: addDays(s, 7));
}

/// The [n]th occurrence of a schedule starting at [anchor].
DateTime nthOccurrence(DateTime anchor, String frequency, int n) {
  switch (frequency) {
    case 'weekly':
      return addDays(anchor, 7 * n);
    case 'biweekly':
      return addDays(anchor, 14 * n);
    case 'semimonthly':
      // anchor day and anchor day + 15 (clamped) each month
      final base = addMonths(anchor, n ~/ 2, anchorDay: anchor.day);
      if (n.isEven) return base;
      final last = DateTime.utc(base.year, base.month + 1, 0).day;
      final d2 = anchor.day + 15;
      return DateTime.utc(base.year, base.month, d2 > last ? last : d2);
    case 'monthly':
      return addMonths(anchor, n, anchorDay: anchor.day);
    case 'yearly':
      return addMonths(anchor, 12 * n, anchorDay: anchor.day);
    default: // once / irregular
      return anchor;
  }
}

/// First occurrence on or after [from]; null for one-shot schedules already past.
DateTime? nextOccurrence(DateTime anchor, String frequency, DateTime from) {
  if (frequency == 'once' || frequency == 'irregular') {
    return anchor.isBefore(from) ? null : anchor;
  }
  var n = 0;
  // jump close first for weekly kinds
  if (frequency == 'weekly' || frequency == 'biweekly') {
    final step = frequency == 'weekly' ? 7 : 14;
    final diff = daysBetween(anchor, from);
    if (diff > 0) n = diff ~/ step;
  }
  var d = nthOccurrence(anchor, frequency, n);
  while (d.isBefore(from)) {
    d = nthOccurrence(anchor, frequency, ++n);
  }
  return d;
}

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String prettyDate(DateTime d) => '${monthNames[d.month - 1]} ${d.day}';
