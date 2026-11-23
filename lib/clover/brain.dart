// Chooses Clover's mood + line from actual FinanceData. Deterministic given (data, history, seed).
import 'dart:math';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import '../domain/finance.dart';
import '../domain/insights.dart';
import 'dialogue.dart';
import 'moods.dart';

class CloverSays {
  final String topic, lineId, text;
  final CloverMood mood;
  const CloverSays(this.topic, this.lineId, this.mood, this.text);
  CloverSays copyText(String t) => CloverSays(topic, lineId, mood, t);
}

/// Event-driven reactions the UI fires after the user records something.
sealed class CloverTrigger {}

class ExpenseLogged extends CloverTrigger {
  final LedgerEvent e;
  ExpenseLogged(this.e);
}

class IncomeLogged extends CloverTrigger {
  final LedgerEvent e;
  final bool extra;
  IncomeLogged(this.e, {this.extra = false});
}

class GoalMoved extends CloverTrigger {
  final LedgerEvent e;
  GoalMoved(this.e);
}

class BillPaid extends CloverTrigger {
  final LedgerEvent e;
  BillPaid(this.e);
}

class TransferLogged extends CloverTrigger {
  final LedgerEvent e;
  TransferLogged(this.e);
}

class CloverBrain {
  /// Recently used line ids, most recent last (persisted by the app).
  final List<String> history;
  final Random rng;
  CloverBrain(this.history, {Random? rng}) : rng = rng ?? Random();

  String _when(FinanceData f, DateTime d) {
    final n = daysBetween(f.todayDate, d);
    if (n == 0) return 'today';
    if (n == 1) return 'tomorrow';
    if (n == -1) return 'yesterday';
    return n > 0 ? 'in $n days' : '${-n} days ago';
  }

  CloverSays? say(String topic, String personality, Map<String, String> data) {
    final pool = (dialogue[topic] ?? const <Line>[]).where((l) => l.fits(personality)).toList();
    if (pool.isEmpty) return null;
    // Anti-repeat: skip lines used recently; window shrinks for small pools so something is always left.
    // Exclude the topic's most recently used lines, always leaving at least one candidate.
    final window = min(pool.length - 1, 12);
    final ids = {for (final l in pool) l.id};
    final recent = history.reversed.where(ids.contains).take(window).toSet();
    var candidates = pool.where((l) => !recent.contains(l.id)).toList();
    if (candidates.isEmpty) candidates = pool;
    candidates.shuffle(rng);
    for (final l in candidates) {
      final text = fillLine(l.text, data);
      if (text != null) return CloverSays(topic, l.id, l.mood, text);
    }
    return null;
  }

  /// Mood + message for the Home screen, based on the current state of the money.
  CloverSays home(FinanceData f, {int? hour}) {
    final p = f.prefs.personality;
    final payday = f.nextPayday;
    final base = {
      'available': formatCents(f.availableToSpend),
      'daily': formatCents(f.dailySafeSpend),
      'payday': payday == null ? 'your horizon' : prettyDate(payday),
      'reserved': formatCents(f.reservedForBills),
    };
    CloverSays? pick(String topic, [Map<String, String> extra = const {}]) => say(topic, p, {...base, ...extra});

    if (!f.hasAnyData) return pick('no_data')!;

    final upcoming = f.upcomingBills(days: 3);
    final overdue = upcoming.where((o) => o.due.isBefore(f.todayDate) && !o.bill.incoming).firstOrNull;
    if (overdue != null) {
      final r = pick('bill_overdue', {'bill': overdue.bill.name, 'amount': formatCents(overdue.remainingCents), 'when': _when(f, overdue.due)});
      if (r != null) return r;
    }
    // Real shortfall: money outside vaults can't cover bills due before payday (budgets don't count here).
    final billShort = f.reservedForBills - (f.totalMoney - f.totalSaved);
    if (billShort > 0 && f.reservedForBills > 0) {
      final r = pick('bills_at_risk', {'short': formatCents(billShort)});
      if (r != null) return r;
    }
    final done = f.goalStatuses.where((g) => g.complete).firstOrNull;
    if (done != null) {
      final r = pick('goal_complete', {'goal': done.goal.name});
      if (r != null) return r;
    }
    final soon = upcoming.where((o) => !o.bill.incoming && !o.due.isBefore(f.todayDate)).firstOrNull;
    if (soon != null) {
      final r = pick('bill_due', {'bill': soon.bill.name, 'amount': formatCents(soon.remainingCents), 'when': _when(f, soon.due)});
      if (r != null) return r;
    }
    final ff = fastFood(f);
    final ffCat = f.categoryByTag('fast_food');
    final ffOver = ffCat?.limitCents != null && ff.total > ffCat!.limitCents!;
    if (ff.visits >= 3 || ffOver) {
      final r = pick('fast_food', {'visits': '${ff.visits}', 'amount': formatCents(ff.total)});
      if (r != null) return r;
    }
    final over = f.categoryStatuses.where((c) => c.over && !c.category.essential).toList()
      ..sort((a, b) => a.remaining.compareTo(b.remaining));
    if (over.isNotEmpty) {
      final r = pick('overspent', {'category': over.first.category.name, 'amount': formatCents(-over.first.remaining)});
      if (r != null) return r;
    }
    for (final g in f.goalStatuses.where((g) => g.goal.tripId != null)) {
      final t = f.trip(g.goal.tripId);
      if (t?.departOn == null) continue;
      final days = daysBetween(f.todayDate, t!.departOn!);
      if (days >= 0 && days <= 45) {
        final r = pick('vacation_near', {'trip': t.name, 'days': '$days', 'pct': '${g.pct}'});
        if (r != null) return r;
      }
    }
    final h = hour ?? f.now.hour;
    if (h >= 23 || h < 5) {
      final r = pick('night');
      if (r != null) return r;
    }
    final daysIn = daysBetween(f.thisWeek.start, f.todayDate);
    final less = f.lastWeekTotals.netSpent - f.weekTotals.netSpent;
    if (daysIn >= 3 && f.lastWeekTotals.netSpent > 0 && less > 0) {
      final r = pick('saved_week', {'amount': formatCents(less)});
      if (r != null) return r;
    }
    if (f.availableToSpend >= 0 && f.dailySafeSpend < f.avgDailySpend() && f.avgDailySpend() > 0) {
      final r = pick('tight');
      if (r != null) return r;
    }
    return pick('idle') ?? const CloverSays('idle', 'fallback', CloverMood.happy, "I'm here. Watching the money.");
  }

  /// Reaction to something the user just recorded. Null when frequency settings say stay quiet.
  CloverSays? react(FinanceData f, CloverTrigger t) {
    final p = f.prefs.personality;
    final freq = f.prefs.frequency;
    switch (t) {
      case ExpenseLogged(:final e):
        final c = f.category(e.categoryId);
        final data = {'amount': formatCents(e.amountCents), 'category': c?.name ?? 'Uncategorized'};
        if (c != null && !c.essential) {
          if (c.tag == 'fast_food') {
            final ff = fastFood(f);
            if (ff.visits >= 3) return say('fast_food', p, {'visits': '${ff.visits}', 'amount': formatCents(ff.total)});
          }
          final st = f.categoryStatus(c);
          if (st.over) return say('overspent', p, {'category': c.name, 'amount': formatCents(-st.remaining)});
        }
        final free = f.availableToSpend + e.amountCents;
        if (free > 0 && e.amountCents * 4 >= free && e.amountCents >= 2000 && !(c?.essential ?? false)) {
          return say('big_expense', p, data);
        }
        if (c?.essential ?? false) return freq == 'low' ? null : say('essential', p, data);
        return freq == 'high' ? say('expense', p, data) : (freq == 'normal' && rng.nextInt(3) == 0 ? say('expense', p, data) : null);
      case IncomeLogged(:final e, :final extra):
        if (e.kind == 'refund') return say('refund', p, {'amount': formatCents(e.amountCents)});
        if (extra) {
          return say('extra_money', p, {'amount': formatCents(e.amountCents), 'source': _sourceLabel(e)});
        }
        return say('income', p, {'amount': formatCents(e.amountCents)});
      case GoalMoved(:final e):
        final g = f.goal(e.goalId);
        if (g == null) return null;
        final s = f.goalStatus(g);
        final data = {'amount': formatCents(e.amountCents), 'goal': g.name, 'pct': '${s.pct}'};
        if (e.kind == 'goal_deposit') return s.complete ? say('goal_complete', p, data) : say('goal_deposit', p, data);
        if (e.reason == 'emergency') return say('emergency_withdraw', p, data);
        if (g.tripId != null) return say('vacation_withdraw', p, data);
        return say('goal_withdraw', p, data);
      case BillPaid(:final e):
        final b = f.bill(e.billId);
        if (b == null) return null;
        final data = {'bill': b.name, 'amount': formatCents(e.amountCents)};
        if (b.isDebt && f.ledger.paidForBill(b.id) >= (b.principalCents ?? 0) + b.feeCents && b.principalCents != null) {
          return say('debt_cleared', p, data);
        }
        return say('bill_paid', p, data);
      case TransferLogged(:final e):
        return freq == 'low' ? null : say('transfer', p, {'amount': formatCents(e.amountCents)});
    }
  }

  CloverSays recap(FinanceData f, WeeklyRecap r) {
    final p = f.prefs.personality;
    final data = {
      'income': formatCents(r.totals.income),
      'spent': formatCents(r.totals.netSpent),
      'saved': formatCents(r.totals.netSaved),
      'change': formatCents(r.spendChange.abs()),
      'weeks': '${r.weeksImproving}',
    };
    CloverSays? pick(String t, [Map<String, String> x = const {}]) => say(t, p, {...data, ...x});
    if (r.empty) return pick('recap_quiet')!;
    final vac = r.vacations.where((v) => v.complete).firstOrNull;
    if (vac != null) return pick('recap_vacation_done', {'goal': vac.goal.name})!;
    if (r.billsAtRisk) return pick('recap_bills_risk')!;
    if (r.totals.netSaved > 0 && r.spendChange <= 0) return pick('recap_great')!;
    if (r.weeksImproving >= 2) return pick('recap_improving')!;
    if (r.spendChange > 0 && r.previous.netSpent > 0 && r.spendChange * 5 > r.previous.netSpent) return pick('recap_overspent')!;
    return pick('recap_mixed')!;
  }

  static String _sourceLabel(LedgerEvent e) => switch (e.incomeSource) {
        'side_job' => 'a side job',
        'tip' => 'tips',
        'gift' => 'a gift',
        'sale' => 'selling stuff',
        _ => e.note?.isNotEmpty == true ? e.note! : 'somewhere',
      };
}
