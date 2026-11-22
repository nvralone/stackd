// Trip totals from the shared trip ledger. Private ledgers are never read across users.
import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import 'finance.dart';

class TripSummary {
  final Trip trip;
  final int planned, paid, saved;
  final Map<String, int> paidByItem;
  final Map<String?, int> savedByMember;
  final int weeksLeft;
  const TripSummary(this.trip, this.planned, this.paid, this.saved, this.paidByItem, this.savedByMember, this.weeksLeft);
  int get budget => trip.budgetCents > 0 ? trip.budgetCents : planned;
  int get remainingCost => (budget - paid).clamp(0, 1 << 40);
  int get stillNeeded => (remainingCost - saved).clamp(0, 1 << 40);
  int get perWeekNeeded => weeksLeft <= 0 ? stillNeeded : ceilDiv(stillNeeded, weeksLeft);
}

TripSummary tripSummary(FinanceData f, Trip t) {
  final entries = f.tripEntries.where((e) => e.tripId == t.id).toList();
  final reversed = {for (final e in entries) if (e.reversesId != null) e.reversesId!};
  final live = entries.where((e) => e.reversesId == null && !reversed.contains(e.id));
  var paid = 0, saved = 0;
  final byItem = <String, int>{};
  final byMember = <String?, int>{};
  for (final e in live) {
    switch (e.kind) {
      case 'expense':
        paid += e.amountCents;
        if (e.itemId != null) byItem[e.itemId!] = (byItem[e.itemId!] ?? 0) + e.amountCents;
      case 'contribution':
        saved += e.amountCents;
        byMember[e.userId] = (byMember[e.userId] ?? 0) + e.amountCents;
      case 'withdrawal':
        saved -= e.amountCents;
        byMember[e.userId] = (byMember[e.userId] ?? 0) - e.amountCents;
    }
  }
  final planned = f.tripItems.where((i) => i.tripId == t.id).fold(0, (s, i) => s + i.plannedCents);
  final weeks = t.departOn == null ? 0 : (daysBetween(f.todayDate, t.departOn!) ~/ 7);
  return TripSummary(t, planned, paid, saved, byItem, byMember, weeks);
}
