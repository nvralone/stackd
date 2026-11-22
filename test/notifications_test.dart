import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/finance.dart';
import 'package:stackd/services/notifications.dart';

import 'helpers.dart';

void main() {
  test('quiet hours across midnight push reminders to the morning', () {
    expect(respectQuietHours(DateTime(2026, 1, 1, 23, 30), 22, 8), DateTime(2026, 1, 2, 8));
    expect(respectQuietHours(DateTime(2026, 1, 1, 3), 22, 8), DateTime(2026, 1, 1, 8));
    expect(respectQuietHours(DateTime(2026, 1, 1, 12), 22, 8), DateTime(2026, 1, 1, 12));
    expect(respectQuietHours(DateTime(2026, 1, 1, 13), 12, 14), DateTime(2026, 1, 1, 14));
  });

  test('planner creates bill, payday and recap reminders and respects toggles', () {
    final bill = Bill(id: 'b', name: 'Rent', amountCents: 90000, frequency: 'monthly', firstDue: addDays(t0, 5));
    final sched = IncomeSchedule(id: 's', name: 'Job', frequency: 'weekly', anchorDate: addDays(t0, 2));
    final f = FinanceData(bills: [bill], schedules: [sched], now: now);
    final plan = planReminders(f, nowLocal: now);
    expect(plan.any((r) => r.key.startsWith('bill:b')), isTrue);
    expect(plan.any((r) => r.key.startsWith('payday:s')), isTrue);
    expect(plan.any((r) => r.key == 'recap'), isTrue);
    final rent = plan.firstWhere((r) => r.key.startsWith('bill:b'));
    expect(rent.at, DateTime(2026, 11, 21, 9)); // 2 days before the 23rd at 9am

    final off = FinanceData(bills: [bill], schedules: [sched], now: now, prefs: Prefs(notifications: {'bills': false, 'payday': false}));
    final plan2 = planReminders(off, nowLocal: now);
    expect(plan2.any((r) => r.key.startsWith('bill:')), isFalse);
    expect(plan2.any((r) => r.key.startsWith('payday:')), isFalse);
  });

  test('no reminders are scheduled during quiet hours', () {
    final bill = Bill(id: 'b', name: 'Rent', amountCents: 100, frequency: 'monthly', firstDue: addDays(t0, 3));
    final f = FinanceData(bills: [bill], now: now, prefs: Prefs(notifications: {'quiet_start': 7, 'quiet_end': 10}));
    for (final r in planReminders(f, nowLocal: now)) {
      expect(r.at.hour >= 7 && r.at.hour < 10, isFalse, reason: r.key);
    }
  });
}
