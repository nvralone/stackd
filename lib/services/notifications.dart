// Local notifications only (no push service). Reminders are recomputed from data after each change.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/dates.dart';
import '../core/money.dart';
import '../domain/finance.dart';

class PlannedReminder {
  final DateTime at; // local wall time
  final String key, title, body;
  const PlannedReminder(this.at, this.key, this.title, this.body);
}

/// Moves a time out of quiet hours [startHour, endHour) to the end of the quiet window.
DateTime respectQuietHours(DateTime t, int startHour, int endHour) {
  bool quiet(int h) => startHour <= endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour);
  if (!quiet(t.hour)) return t;
  var d = DateTime(t.year, t.month, t.day, endHour);
  if (!d.isAfter(t)) d = d.add(const Duration(days: 1));
  return d;
}

/// Pure planner: which reminders should exist for the next 30 days.
List<PlannedReminder> planReminders(FinanceData f, {DateTime? nowLocal}) {
  final now = nowLocal ?? DateTime.now();
  final p = f.prefs;
  final out = <PlannedReminder>[];
  DateTime at(DateTime date, int hour) => DateTime(date.year, date.month, date.day, hour);

  if (p.notif('payday')) {
    for (final s in f.schedules.where((s) => s.active && s.frequency != 'irregular')) {
      final d = nextOccurrence(s.anchorDate, s.frequency, f.todayDate);
      if (d != null) out.add(PlannedReminder(at(d, 9), 'payday:${s.id}', 'Payday', '${s.name} is expected today. Log it and split it with Clover.'));
    }
  }
  for (final o in f.upcomingBills(days: 30)) {
    if (o.bill.incoming) continue;
    if (o.due.isBefore(f.todayDate)) {
      if (p.notif('overdue')) {
        out.add(PlannedReminder(now.add(const Duration(minutes: 1)), 'overdue:${o.bill.id}:${o.index}', 'Overdue bill',
            '${o.bill.name}: ${formatCents(o.remainingCents)} was due ${prettyDate(o.due)}.'));
      }
    } else if (p.notif('bills')) {
      out.add(PlannedReminder(at(addDays(o.due, -o.bill.reminderDays), 9), 'bill:${o.bill.id}:${o.index}', 'Bill coming up',
          '${o.bill.name}: ${formatCents(o.remainingCents)} due ${prettyDate(o.due)}.'));
    }
  }
  if (p.notif('savings')) {
    for (final g in f.goalStatuses.where((g) => !g.complete && g.goal.contributionCents > 0 && g.goal.contributionFreq == 'weekly')) {
      final d = addDays(f.thisWeek.start, 7);
      out.add(PlannedReminder(at(d, 10), 'save:${g.goal.id}', 'Savings reminder', 'Planned ${formatCents(g.goal.contributionCents)} for ${g.goal.name}.'));
    }
  }
  if (p.notif('recap')) {
    out.add(PlannedReminder(at(addDays(f.thisWeek.start, 7), 9), 'recap', 'Weekly recap ready', 'Clover has your week in review.'));
  }
  return [
    for (final r in out)
      PlannedReminder(respectQuietHours(r.at.isBefore(now) ? now.add(const Duration(minutes: 1)) : r.at, p.quietStart, p.quietEnd),
          r.key, r.title, r.body)
  ];
}

class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  final _details = const NotificationDetails(
    android: AndroidNotificationDetails('stackd_reminders', 'Reminders', importance: Importance.defaultImportance),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      _ready = await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(),
              windows: WindowsInitializationSettings(
                  appName: 'STACKD', appUserModelId: 'com.stackd.stackd', guid: 'b8a7c6d2-4f3e-4a1b-9c8d-7e6f5a4b3c2d'),
            ),
          ) ??
          false;
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  Future<void> reschedule(List<PlannedReminder> plan) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      for (final r in plan.take(40)) {
        await _plugin.zonedSchedule(
          id: r.key.hashCode & 0x7fffffff,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
        );
      }
    } catch (e) {
      debugPrint('schedule failed: $e');
    }
  }

  /// Immediate alert (spending limit, vacation milestone). Suppressed during quiet hours.
  Future<void> now(String title, String body, {required int quietStart, required int quietEnd}) async {
    if (!_ready) return;
    final t = DateTime.now();
    if (respectQuietHours(t, quietStart, quietEnd) != t) return;
    try {
      await _plugin.show(id: title.hashCode & 0x7fffffff, title: title, body: body, notificationDetails: _details);
    } catch (_) {}
  }
}
