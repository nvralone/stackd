// Renders screenshots of the app with SAMPLE data (not anyone's real records) for design review.
//   flutter test tool/screens_test.dart --update-goldens   -> PNGs in tool/screens/
// Skipped unless SCREENS=1.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stackd/core/dates.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/domain/allocation.dart';
import 'package:stackd/state/app_state.dart';
import 'package:stackd/ui/app.dart';
import 'package:stackd/ui/common.dart';
import 'package:stackd/ui/sheets/allocation_sheet.dart';

final clock = DateTime(2026, 11, 23, 12);

Future<void> loadFonts() async {
  const dir = r'C:\src\flutter\bin\cache\artifacts\material_fonts';
  Future<ByteData> f(String n) async => ByteData.sublistView(await File('$dir\\$n').readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(f('roboto-regular.ttf'))
        ..addFont(f('roboto-medium.ttf'))
        ..addFont(f('roboto-bold.ttf'))
        ..addFont(f('roboto-black.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'))).load();
}

AppState sample() {
  final app = AppState(LocalDb.memory(), clock: () => clock);
  app.ensureDefaults();
  app.createAccount(MoneyAccount(id: 'cash', name: 'Money'), 32000);
  app.createAccount(MoneyAccount(id: 'ca', name: 'Cash App', kind: 'cashapp'), 3054);
  app.save(IncomeSchedule(id: 'pay', name: 'Job', frequency: 'weekly', anchorDate: day(2026, 11, 27), expectedCents: 29500));
  for (final c in app.data.categories.where((c) => ['Groceries', 'Gas'].contains(c.name))) {
    app.save(c..limitCents = c.name == 'Gas' ? 6000 : 15000);
  }
  app.save(Category(id: 'fun', name: 'Fun', color: 0xFFB39DFF, limitCents: 8000));
  app.save(Bill(id: 'b1', name: 'Cash App Borrow', amountCents: 2509, frequency: 'weekly', firstDue: day(2026, 11, 27)));
  app.save(Bill(id: 'b2', name: 'Insurance', amountCents: 20000, frequency: 'monthly', firstDue: day(2026, 12, 7)));
  app.save(Bill(id: 'b3', name: 'Suno', amountCents: 3000, frequency: 'monthly', firstDue: day(2026, 12, 10)));
  app.save(SavingsGoal(id: 'g1', name: 'The VAULT', goalCents: 200000, color: 0xFF7BD88F, locked: true));
  app.save(SavingsGoal(id: 'g2', name: 'E-FUND', goalCents: 150000, color: 0xFF7FB2FF));
  app.save(Trip(id: 't1', name: 'The Trip', destination: 'Canada'));
  app.save(SavingsGoal(id: 'g3', name: 'The Trip', goalCents: 300000, tripId: 't1'));
  app.record([
    app.event(kind: 'goal_deposit', amountCents: 3000, goalId: 'g1'),
    app.event(kind: 'goal_deposit', amountCents: 4000, goalId: 'g2'),
    app.event(kind: 'goal_deposit', amountCents: 4000, goalId: 'g3'),
    app.event(kind: 'expense', amountCents: 1250, accountId: 'cash', categoryId: app.data.categories.firstWhere((c) => c.name == 'Groceries').id),
  ]);
  app.addToBillEnvelope(2000);
  app.savePrefs((p) {
    p.onboarded = true;
    p.displayName = 'Alex';
  });
  return app;
}

Future<void> shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 900));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/$name.png'));
}

void main() {
  final on = Platform.environment['SCREENS'] == '1';
  testWidgets('screens', (t) async {
    await t.runAsync(loadFonts);
    final app = sample();
    for (final (name, size) in [('desktop', const Size(1440, 900)), ('phone', const Size(390, 844))]) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(StackdApp(app: app));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // decode sprite images
      await shot(t, '${name}_home');
      for (final (i, tab) in [(2, 'budget'), (3, 'goals'), (4, 'bills'), (6, 'settings')]) {
        Shell.go(t.element(find.byType(Scaffold).first), i);
        await t.pump(const Duration(milliseconds: 400));
        await shot(t, '${name}_$tab');
      }
      Shell.go(t.element(find.byType(Scaffold).first), 0);
      await t.pump(const Duration(milliseconds: 400));
    }
    // Paycheck split sheet on phone
    final ctx = t.element(find.byType(Scaffold).first);
    final p = suggestPaycheck(app.data, 29500);
    sheet(ctx, AllocationSheet(title: 'Split your paycheck', amount: 29500, groupId: 'x', date: today(clock), suggested: p));
    await t.pump(const Duration(milliseconds: 800));
    await shot(t, 'phone_split');
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
    t.view.reset();
  }, skip: !on);
}
