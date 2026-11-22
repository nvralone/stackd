import 'package:stackd/core/dates.dart';
import 'package:stackd/core/ids.dart';
import 'package:stackd/data/models.dart';

/// Fixed "now": Wednesday 2026-11-18 12:00 local.
final now = DateTime(2026, 11, 18, 12);
final t0 = today(now);

LedgerEvent ev(String kind, int cents,
        {String? acct, String? to, String? cat, String? goal, String? bill, int? occ, DateTime? on, String? src, String? reason, String? reverses, String? trip}) =>
    LedgerEvent(id: newId(), kind: kind, amountCents: cents, occurredOn: on ?? t0, accountId: acct, toAccountId: to,
        categoryId: cat, goalId: goal, billId: bill, billOccurrence: occ, incomeSource: src, reason: reason, reversesId: reverses, tripId: trip);
