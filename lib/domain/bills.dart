// Deterministic bill & debt schedules. Payments only count once the user records them.
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'ledger.dart';

enum OccStatus { paid, partial, overdue, dueSoon, upcoming, skipped }

class BillOccurrence {
  final Bill bill;
  final int index;
  final DateTime due;
  final int amountCents, paidCents;
  final OccStatus status;
  final bool setAside; // money is ready, bill not paid yet
  const BillOccurrence(this.bill, this.index, this.due, this.amountCents, this.paidCents, this.status, {this.setAside = false});
  bool get isLast => paymentCountOf(bill) != null && index == paymentCountOf(bill)! - 1 && bill.frequency != 'once';
  int get remainingCents => (amountCents - paidCents).clamp(0, amountCents);
  bool get open => status != OccStatus.paid && status != OccStatus.skipped;
}

/// First due date on or after [from] for a schedule anchored at [first] (unchanged if already upcoming).
DateTime rollForward(DateTime first, String frequency, DateTime from) =>
    first.isBefore(from) ? (nextOccurrence(first, frequency, from) ?? first) : first;

/// Total the agreement asks for: principal + fees for debts, otherwise amount * count (null = open-ended).
int? totalOwed(Bill b) {
  if (b.isDebt && b.principalCents != null) return b.principalCents! + b.feeCents;
  if (b.frequency == 'once') return b.amountCents;
  return b.paymentCount == null ? null : b.amountCents * b.paymentCount!;
}

/// Number of scheduled payments, or null for open-ended recurring bills.
int? paymentCountOf(Bill b) {
  if (b.frequency == 'once') return 1;
  if (b.paymentCount != null) return b.paymentCount;
  final owed = totalOwed(b);
  return owed == null ? null : ceilDiv(owed, b.amountCents);
}

/// Amount scheduled for occurrence [i]; the final debt payment is the remainder.
int scheduledAmount(Bill b, int i) {
  final n = paymentCountOf(b);
  final owed = totalOwed(b);
  if (n == null || owed == null || !b.isDebt) return b.amountCents;
  if (i == n - 1) return owed - b.amountCents * (n - 1);
  return b.amountCents;
}

/// Occurrences with due date < [until] (all past ones included so overdue items surface).
List<BillOccurrence> occurrences(Bill b, Ledger ledger, List<BillOverride> overrides, DateTime until, {DateTime? now}) {
  final t = today(now);
  final n = paymentCountOf(b);
  final ov = {for (final o in overrides) if (o.billId == b.id && !o.deleted) o.occurrence: o};
  final out = <BillOccurrence>[];
  for (var i = 0; n == null || i < n; i++) {
    final natural = nthOccurrence(b.firstDue, b.frequency, i);
    if (!natural.isBefore(until) && (ov[i]?.dueOn == null || !ov[i]!.dueOn!.isBefore(until))) break;
    final due = ov[i]?.dueOn ?? natural;
    if (!due.isBefore(until)) continue;
    final amt = scheduledAmount(b, i);
    final paid = ledger.paidFor(b.id, i);
    OccStatus st;
    if (ov[i]?.skipped == true) {
      st = OccStatus.skipped;
    } else if (paid >= amt) {
      st = OccStatus.paid;
    } else if (due.isBefore(t)) {
      st = OccStatus.overdue;
    } else if (paid > 0) {
      st = OccStatus.partial;
    } else if (daysBetween(t, due) <= b.reminderDays) {
      st = OccStatus.dueSoon;
    } else {
      st = OccStatus.upcoming;
    }
    out.add(BillOccurrence(b, i, due, amt, paid, st, setAside: ov[i]?.setAside ?? false));
    if (b.frequency == 'once') break;
  }
  return out;
}

/// Remaining balance on a debt agreement (null for open-ended bills).
int? remainingOwed(Bill b, Ledger ledger) {
  final owed = totalOwed(b);
  return owed == null ? null : (owed - ledger.paidForBill(b.id)).clamp(0, owed);
}

/// Unpaid outgoing obligations due before [until], including overdue ones. Incoming debts are excluded.
/// [earmarks]: money already set aside per bill elsewhere (Bill envelope); it reduces that bill's amount.
int obligationsUntil(List<Bill> bills, Ledger ledger, List<BillOverride> overrides, DateTime until,
    {DateTime? now, Map<String, int> earmarks = const {}}) {
  var s = 0;
  for (final b in bills) {
    if (b.archived || b.deleted || b.incoming) continue;
    var owed = 0;
    for (final o in occurrences(b, ledger, overrides, until, now: now)) {
      if (o.open) owed += o.remainingCents;
    }
    final held = earmarks[b.id] ?? 0;
    s += owed > held ? owed - held : 0;
  }
  return s;
}

/// Next open occurrence of a bill (first unpaid, possibly overdue).
BillOccurrence? nextOpen(Bill b, Ledger ledger, List<BillOverride> overrides, {DateTime? now}) {
  final horizon = addDays(today(now), 400);
  for (final o in occurrences(b, ledger, overrides, horizon, now: now)) {
    if (o.open) return o;
  }
  return null;
}
