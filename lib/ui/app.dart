import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import 'common.dart';
import 'screens/activity.dart';
import 'screens/auth.dart';
import 'screens/bills.dart';
import 'screens/budget.dart';
import 'screens/goals.dart';
import 'screens/home.dart';
import 'screens/insights.dart';
import 'screens/onboarding.dart';
import 'screens/settings.dart';
import 'sheets/entry_sheet.dart';
import 'theme.dart';

class StackdApp extends StatelessWidget {
  final AppState app;
  const StackdApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) => AppScope(
        app: app,
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => MaterialApp(
            title: 'STACKD',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: switch (app.prefs.theme) { 'light' => ThemeMode.light, 'system' => ThemeMode.system, _ => ThemeMode.dark },
            home: const Gate(),
          ),
        ),
      );
}

/// Auth -> onboarding -> main shell.
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.needsAuth) return const AuthScreen();
    if (!app.prefs.onboarded) return const OnboardingScreen();
    return const Shell();
  }
}

class Dest {
  final String label;
  final IconData icon, selected;
  final Widget page;
  const Dest(this.label, this.icon, this.selected, this.page);
}

const destinations = [
  Dest('Home', Icons.home_outlined, Icons.home_rounded, HomeScreen()),
  Dest('Activity', Icons.receipt_long_outlined, Icons.receipt_long_rounded, ActivityScreen()),
  Dest('Budget', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded, BudgetScreen()),
  Dest('Goals', Icons.savings_outlined, Icons.savings_rounded, GoalsScreen()),
  Dest('Bills', Icons.event_note_outlined, Icons.event_note_rounded, BillsScreen()),
  Dest('Insights', Icons.insights_outlined, Icons.insights_rounded, InsightsScreen()),
  Dest('Settings', Icons.settings_outlined, Icons.settings_rounded, SettingsScreen()),
];

class Shell extends StatefulWidget {
  const Shell({super.key});
  static void go(BuildContext context, int i) => context.findAncestorStateOfType<_ShellState>()?.go(i);
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  void go(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    final wide = context.wide;
    final fab = FloatingActionButton.extended(
      heroTag: 'quickadd',
      onPressed: () => openQuickAdd(context),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Quick Add'),
    );
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(key: ValueKey(index), child: destinations[index].page),
    );
    if (wide) {
      return Scaffold(
        floatingActionButton: index == 6 ? null : fab,
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: index,
            onDestinationSelected: go,
            labelType: MediaQuery.sizeOf(context).width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Image.asset('assets/clover/clover_base.png', width: 40, filterQuality: FilterQuality.none),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    // Mobile: six tabs in the bottom bar; Settings sits in each page's app bar.
    return Scaffold(
      body: body,
      floatingActionButton: index == 6 ? null : fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index.clamp(0, 5) == index ? index : 0,
        onDestinationSelected: go,
        destinations: [
          for (final d in destinations.take(6)) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
        ],
      ),
    );
  }
}

/// Standard top bar for main pages, with a Settings shortcut on mobile.
class PageBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  const PageBar(this.title, {super.key, this.actions = const []});
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => AppBar(
        title: Text(title),
        toolbarHeight: 64,
        actions: [
          ...actions,
          if (!context.wide && title != 'Settings')
            IconButton(tooltip: 'Settings', onPressed: () => Shell.go(context, 6), icon: const Icon(Icons.settings_rounded)),
          const SizedBox(width: 8),
        ],
      );
}
