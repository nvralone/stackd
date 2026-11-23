import 'package:material_ui/material_ui.dart';

import '../clover/clover_widget.dart';
import '../clover/moods.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'pixel.dart';
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
            title: 'STAKD',
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
    if (app.firstSyncPending) return const _SyncingScreen();
    if (!app.prefs.onboarded) return const OnboardingScreen();
    return const Shell();
  }
}

/// Shown while a newly signed-in device downloads the account's data.
class _SyncingScreen extends StatelessWidget {
  const _SyncingScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CloverSprite(mood: CloverMood.thinking, size: 120),
            const SizedBox(height: 16),
            const Text('Grabbing your stuff from the cloud...', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const SizedBox(width: 160, child: LinearProgressIndicator()),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => context.appRead.skipFirstSync(),
              child: const Text('Skip and continue'),
            ),
          ]),
        ),
      );
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
        floatingActionButton: index == 6 || index == 0 ? null : fab,
        body: Row(children: [
          SideNav(index: index, onSelect: go),
          Expanded(child: body),
        ]),
      );
    }    // Mobile: six tabs in the bottom bar; Settings sits in each page's app bar.
    return Scaffold(
      body: body,
      floatingActionButton: index == 6 || index == 0 ? null : fab,
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

/// Desktop / tablet navigation: pixel logo, pill buttons, a little night scene with Clover at the bottom.
class SideNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const SideNav({super.key, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final full = MediaQuery.sizeOf(context).width >= 1200;
    return Container(
      width: full ? 232 : 88,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Tones.bgDark2, Tones.bgDark] : const [Color(0xFFE9E1FB), Tones.bgLight],
        ),
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        child: Column(children: [
          SizedBox(height: full ? 16 : 24),
          if (full)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Image.asset('assets/brand/stakd_logo.png', width: 200, filterQuality: FilterQuality.medium, semanticLabel: 'STAKD'),
            )
          else
            Image.asset('assets/clover/clover_base.png', width: 44, filterQuality: FilterQuality.none),
          SizedBox(height: full ? 16 : 28),
          for (var i = 0; i < destinations.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: full ? 14 : 10, vertical: 3),
              child: _NavItem(d: destinations[i], selected: i == index, full: full, onTap: () => onSelect(i)),
            ),
          const Spacer(),
          SizedBox(
            height: 120,
            child: Stack(fit: StackFit.expand, children: [
              NightScene(tint: cs.primary, phone: true),
              const Positioned(left: 12, bottom: 6, child: CloverSprite(mood: CloverMood.sleepy, size: 52)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final Dest d;
  final bool selected, full;
  final VoidCallback onTap;
  const _NavItem({required this.d, required this.selected, required this.full, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    return Tooltip(
      message: full ? '' : d.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? cs.primary.withValues(alpha: 0.75) : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: full ? 14 : 0, vertical: 12),
            child: Row(mainAxisAlignment: full ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
              Icon(selected ? d.selected : d.icon, color: selected ? cs.primary : fg, size: 24),
              if (full) ...[
                const SizedBox(width: 14),
                Text(d.label, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg)),
              ],
            ]),
          ),
        ),
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
        title: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: PixelText(title, size: 20, shadow: context.cs.primary.withValues(alpha: 0.45))),
        toolbarHeight: 64,
        actions: [
          ...actions,
          if (!context.wide && title != 'Settings')
            IconButton(tooltip: 'Settings', onPressed: () => Shell.go(context, 6), icon: const Icon(Icons.settings_rounded)),
          const SizedBox(width: 8),
        ],
      );
}
