import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stackd/data/local_db.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/state/app_state.dart';
import 'package:stackd/ui/app.dart';

import 'helpers.dart';

AppState readyApp() {
  final app = AppState(LocalDb.memory(), clock: () => now);
  app.ensureDefaults();
  app.createAccount(MoneyAccount(id: 'cash', name: 'Cash'), 10000);
  app.savePrefs((p) => p.onboarded = true);
  return app;
}

Future<void> pumpAt(WidgetTester t, AppState app, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(StackdApp(app: app));
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> settle(WidgetTester t) async {
  await t.pump(const Duration(seconds: 4)); // flush debounce timers
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('mobile: bottom navigation with six tabs and Settings in app bar', (t) async {
    final app = readyApp();
    await pumpAt(t, app, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(6));
    expect(find.text('SPARE MONEY (YOURS TO SPEND)'), findsOneWidget);
    await t.tap(find.text('Bills').last);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Next 30 days'), findsWidgets);
    await t.tap(find.byTooltip('Settings').first);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Money accounts'), findsOneWidget);
    await settle(t);
  });

  testWidgets('desktop (Windows-size window): sidebar navigation, no overflow', (t) async {
    final app = readyApp();
    await pumpAt(t, app, const Size(1366, 768));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['Activity', 'Budget', 'Goals', 'Bills', 'Insights', 'Settings', 'Home']) {
      await t.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(label)));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: label);
    }
    await settle(t);
  });

  testWidgets('narrow phone renders every tab without layout errors', (t) async {
    final app = readyApp();
    await pumpAt(t, app, const Size(320, 640));
    for (final label in ['Activity', 'Budget', 'Goals', 'Bills', 'Insights', 'Home']) {
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(destinations.firstWhere((d) => d.label == label).icon)));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: label);
    }
    await settle(t);
  });

  testWidgets('Quick Add records an expense and updates balances', (t) async {
    final app = readyApp();
    await pumpAt(t, app, const Size(430, 932));
    await t.tap(find.text('Quick Add'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.enterText(find.byType(TextFormField).first, '12.34');
    final picker = find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>).first;
    await t.ensureVisible(picker);
    await t.pump();
    await t.tap(picker);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Groceries').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pump(const Duration(milliseconds: 600));
    expect(app.data.ledger.accountBalance('cash'), 10000 - 1234);
    expect(app.data.weekTotals.netSpent, 1234);
    await settle(t);
  });

  testWidgets('first run shows onboarding', (t) async {
    final app = AppState(LocalDb.memory(), clock: () => now);
    await pumpAt(t, app, const Size(390, 844));
    expect(find.text('Welcome to STACKD'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Your money accounts'), findsOneWidget);
    await settle(t);
  });
}
