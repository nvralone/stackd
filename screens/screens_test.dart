// Renders real-font screenshots of key screens (not part of the regular suite).
// Run: flutter test screens/screens_test.dart --update-goldens   -> PNGs in screens/out/
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/state/app_state.dart';
import 'package:stackd/ui/app.dart';

final now = DateTime(2026, 11, 18, 12);

Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$dir/materialicons-regular.otf').readAsBytesSync())));
  await icons.load();
}

AppState demo() {
  final app = AppState(LocalDb.memory(), clock: () => now);
  app.ensureDefaults();
  final d0 = today(now);
  app.createAccount(MoneyAccount(id: 'cash', name: 'Cash', kind: 'cash', color: 0xFF81C784), 8500);
  app.createAccount(MoneyAccount(id: 'chk', name: 'Checking', kind: 'checking', color: 0xFF7986CB), 64250);
  app.save(IncomeSchedule(id: 's', name: 'Job', frequency: 'weekly', anchorDate: addDays(d0, 2), expectedCents: 52000));
  app.save(SavingsGoal(id: 'ef', name: 'Emergency Fund', goalCents: 100000, contributionCents: 4000, color: 0xFF7BD88F));
  app.save(Trip(id: 't', name: 'Miami', destination: 'Miami, FL', departOn: addDays(d0, 40), budgetCents: 90000));
  app.save(SavingsGoal(id: 'mi', name: 'Miami', goalCents: 90000, tripId: 't', targetDate: addDays(d0, 40), color: 0xFFB39DFF));
  app.save(Bill(id: 'b1', name: 'Phone', amountCents: 4500, frequency: 'monthly', firstDue: addDays(d0, 2)));
  app.save(Bill(id: 'b2', name: 'Cash App Borrow', kind: 'debt_owed', amountCents: 1000, frequency: 'weekly', firstDue: addDays(d0, 2), principalCents: 6000));
  final ff = app.data.categoryByTag('fast_food')!;
  final gro = app.data.categoryByTag('groceries')!;
  app.save(ff..limitCents = 3000);
  app.record([
    app.event(kind: 'goal_deposit', amountCents: 32000, goalId: 'ef', on: addDays(d0, -10)),
    app.event(kind: 'goal_deposit', amountCents: 41000, goalId: 'mi', on: addDays(d0, -6)),
    app.event(kind: 'income', amountCents: 51800, accountId: 'chk', incomeSource: 'paycheck', on: addDays(d0, -1)),
    app.event(kind: 'expense', amountCents: 1249, accountId: 'cash', categoryId: ff.id, on: addDays(d0, -1)),
    app.event(kind: 'expense', amountCents: 6420, accountId: 'chk', categoryId: gro.id, on: addDays(d0, -2)),
    app.event(kind: 'expense', amountCents: 2210, accountId: 'chk', categoryId: gro.id, on: addDays(d0, -9)),
    app.event(kind: 'expense', amountCents: 1890, accountId: 'cash', categoryId: ff.id, on: addDays(d0, -8)),
  ]);
  app.savePrefs((p) => p
    ..onboarded = true
    ..displayName = 'Money Man');
  app.refreshHomeClover();
  return app;
}

Future<void> shot(WidgetTester t, String name, Size size, {int tab = 0, String theme = 'dark'}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final app = demo();
  app.savePrefs((p) => p.theme = theme);
  await t.pumpWidget(StackdApp(app: app));
  await t.pump(const Duration(milliseconds: 500));
  if (tab != 0) {
    await t.tap(find.byIcon(destinations[tab].icon).first);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // decode sprite
  await t.pump(const Duration(milliseconds: 100));
  await expectLater(find.byType(StackdApp), matchesGoldenFile('out/$name.png'));
  await t.pump(const Duration(seconds: 4));
  await t.pumpWidget(const SizedBox());
}

void main() {
  setUpAll(loadFonts);
  testWidgets('home mobile', (t) => shot(t, 'home_mobile', const Size(390, 1500)));
  testWidgets('home light', (t) => shot(t, 'home_mobile_light', const Size(390, 1100), theme: 'light'));
  testWidgets('home desktop', (t) => shot(t, 'home_desktop', const Size(1366, 900)));
  testWidgets('budget', (t) => shot(t, 'budget_mobile', const Size(390, 1300), tab: 2));
  testWidgets('goals', (t) => shot(t, 'goals_mobile', const Size(390, 1000), tab: 3));
  testWidgets('bills', (t) => shot(t, 'bills_desktop', const Size(1366, 900), tab: 4));
  testWidgets('insights', (t) => shot(t, 'insights_mobile', const Size(390, 1500), tab: 5));
}
