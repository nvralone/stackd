import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/clover/brain.dart';
import 'package:stackd/clover/dialogue.dart';
import 'package:stackd/clover/moods.dart';
import 'package:stackd/clover/voice.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/domain/insights.dart';

import 'helpers.dart';

final cash = MoneyAccount(id: 'cash', name: 'Cash');
final ff = Category(id: 'ff', name: 'Fast Food', color: 0, tag: 'fast_food', limitCents: 2000);
final rent = Category(id: 'rent', name: 'Rent', color: 0, essential: true);
final beach = SavingsGoal(id: 'beach', name: 'Beach Trip', goalCents: 50000, tripId: 't1');
final ef = SavingsGoal(id: 'ef', name: 'Emergency Fund', goalCents: 100000);

FinanceData fin(List<LedgerEvent> e, {List<Bill> bills = const [], String personality = 'chaotic', String freq = 'normal', DateTime? at}) => FinanceData(
    accounts: [cash], categories: [ff, rent], goals: [beach, ef], bills: bills, events: e,
    prefs: Prefs(clover: {'personality': personality, 'frequency': freq}), now: at ?? now);

CloverBrain brain() => CloverBrain([], rng: Random(1));

void main() {
  test('20 moods exist with distinct sprite paths', () {
    expect(CloverMood.values.length, 20);
    expect(CloverMood.values.map((m) => m.spritePath).toSet().length, 20);
    expect(CloverMood.dollarEyes.spritePath, 'assets/clover/moods/dollar_eyes.png');
  });

  test('every topic has a line for every personality', () {
    for (final entry in dialogue.entries) {
      for (final p in ['friendly', 'chaotic', 'savage']) {
        expect(entry.value.any((l) => l.fits(p)), isTrue, reason: '${entry.key} has no $p line');
      }
    }
  });

  test('line ids are unique', () {
    final ids = dialogue.values.expand((l) => l).map((l) => l.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('missing data makes a line unusable instead of inventing values', () {
    expect(fillLine('You saved {amount}!', {}), isNull);
    expect(fillLine('You saved {amount}!', {'amount': '\$5.00'}), 'You saved \$5.00!');
  });

  group('home mood selection', () {
    test('no data -> intro', () {
      expect(brain().home(fin([])).topic, 'no_data');
    });

    test('overdue bill beats everything', () {
      final b = Bill(id: 'b', name: 'Phone', amountCents: 4500, frequency: 'monthly', firstDue: addDays(t0, -2));
      final s = brain().home(fin([ev('opening', 100000, acct: 'cash')], bills: [b]), hour: 12);
      expect(s.topic, 'bill_overdue');
      expect(s.text, contains('Phone'));
      expect(s.text, contains('\$45.00'));
    });

    test('bills exceeding free money -> panicking', () {
      final b = Bill(id: 'b', name: 'Rent', amountCents: 90000, frequency: 'monthly', firstDue: addDays(t0, 5), reminderDays: 0);
      final s = brain().home(fin([ev('opening', 10000, acct: 'cash')], bills: [b]), hour: 12);
      expect(s.topic, 'bills_at_risk');
      expect(s.mood, anyOf(CloverMood.panicking, CloverMood.thinking, CloverMood.shocked));
    });

    test('fast food streak -> fast food roast with real numbers', () {
      final e = [ev('opening', 50000, acct: 'cash'), for (var i = 0; i < 3; i++) ev('expense', 900, acct: 'cash', cat: 'ff')];
      final s = brain().home(fin(e), hour: 12);
      expect(s.topic, 'fast_food');
      expect(s.text, anyOf(contains('3'), contains('\$27.00')));
    });

    test('essential overspending never triggers scolding', () {
      final r = Category(id: 'rent', name: 'Rent', color: 0, essential: true, limitCents: 100);
      final f = FinanceData(accounts: [cash], categories: [r], events: [ev('opening', 100000, acct: 'cash'), ev('expense', 90000, acct: 'cash', cat: 'rent')], now: now);
      expect(brain().home(f, hour: 12).topic, isNot('overspent'));
    });
  });

  group('reactions', () {
    test('emergency withdrawal is supportive, not punished', () {
      final w = ev('goal_withdraw', 5000, goal: 'ef', reason: 'emergency');
      final s = brain().react(fin([ev('goal_deposit', 20000, goal: 'ef'), w]), GoalMoved(w))!;
      expect(s.topic, 'emergency_withdraw');
      expect(s.mood, anyOf(CloverMood.determined, CloverMood.thinking));
    });

    test('vacation withdrawal begs', () {
      final w = ev('goal_withdraw', 5000, goal: 'beach', reason: 'other');
      final s = brain().react(fin([ev('goal_deposit', 20000, goal: 'beach'), w]), GoalMoved(w))!;
      expect(s.topic, 'vacation_withdraw');
    });

    test('completing a goal celebrates', () {
      final d = ev('goal_deposit', 50000, goal: 'beach');
      final s = brain().react(fin([d]), GoalMoved(d))!;
      expect(s.topic, 'goal_complete');
    });

    test('low frequency stays quiet for routine expenses', () {
      final e = ev('expense', 300, acct: 'cash', cat: 'rent');
      expect(brain().react(fin([ev('opening', 100000, acct: 'cash'), e], freq: 'low'), ExpenseLogged(e)), isNull);
    });

    test('personality filters lines', () {
      final e = ev('income', 50000, acct: 'cash', src: 'paycheck');
      for (var i = 0; i < 20; i++) {
        final s = CloverBrain([], rng: Random(i)).react(fin([e], personality: 'friendly'), IncomeLogged(e))!;
        expect(dialogue['income']!.firstWhere((l) => l.id == s.lineId).fits('friendly'), isTrue);
      }
    });
  });

  test('anti-repeat: no back-to-back repeats within a topic', () {
    final b = CloverBrain([], rng: Random(3));
    String? last;
    for (var i = 0; i < 30; i++) {
      final s = b.say('expense', 'chaotic', {'amount': '\$1.00', 'category': 'Snacks'})!;
      expect(s.lineId, isNot(last));
      last = s.lineId;
      b.history.add(s.lineId);
    }
  });

  group('weekly recap', () {
    test('great week vs overspent week', () {
      final prevWeek = addDays(weekStartOf(t0, 1), -7);
      final great = fin([
        ev('income', 60000, acct: 'cash', src: 'paycheck', on: prevWeek),
        ev('goal_deposit', 10000, goal: 'ef', on: prevWeek),
        ev('expense', 3000, acct: 'cash', cat: 'ff', on: prevWeek),
        ev('expense', 9000, acct: 'cash', cat: 'ff', on: addDays(prevWeek, -7)),
      ]);
      final r = buildRecap(great);
      expect(r.totals.income, 60000);
      expect(r.totals.netSaved, 10000);
      expect(brain().recap(great, r).topic, 'recap_great');

      final bad = fin([
        ev('expense', 3000, acct: 'cash', cat: 'ff', on: addDays(prevWeek, -7)),
        ev('expense', 9000, acct: 'cash', cat: 'ff', on: prevWeek),
      ]);
      expect(brain().recap(bad, buildRecap(bad)).topic, 'recap_overspent');
      expect(brain().recap(fin([]), buildRecap(fin([]))).topic, 'recap_quiet');
    });
  });

  test('babble synth produces a valid WAV', () {
    final w = synthBabble('WAIT YOU ACTUALLY STUCK TO THE BUDGET', CloverMood.excited.pitch);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    expect(w.length, greaterThan(44 + 1000));
    expect(synthBabble('x', 1.0), synthBabble('x', 1.0)); // deterministic
  });
}
