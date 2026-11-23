import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../clover/brain.dart';
import '../../clover/clover_widget.dart';
import '../../core/dates.dart';
import '../../domain/bills.dart';
import '../app.dart';
import '../common.dart';
import '../pixel.dart';
import '../sheets/afford_sheet.dart';
import '../sheets/entry_sheet.dart';
import '../sheets/money_sheets.dart';
import '../theme.dart';
import 'bills.dart';
import 'goals.dart';
import 'plan.dart';

const homeWidgets = {
  'clover': 'Clover',
  'available': 'Safe to spend',
  'stats': 'Money overview',
  'week': 'This week',
  'budgets': 'Budgets this week',
  'actions': 'Quick actions',
  'bills': 'Upcoming bills',
  'goals': 'Savings progress',
  'accounts': 'Accounts',
};

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final hidden = List<String>.from(app.prefs.clover['home_hidden'] as List? ?? const []);
    bool show(String k) => !hidden.contains(k);
    final says = app.cloverNow ?? app.brain.home(d);
    final grid = context.wide ? 4 : 2;
    final upcoming = d.upcomingBills(days: 14).where((o) => !o.bill.incoming).take(4).toList();

    final payday = d.nextPayday;
    final daysToPay = payday == null ? null : daysBetween(d.todayDate, payday);
    final envelope = d.billEnvelopeBalance;
    final spentPct = d.weekTotals.income <= 0 ? null : (d.weekTotals.netSpent / d.weekTotals.income).clamp(0.0, 1.0);
    var i = 0;
    Widget enter(Widget w) => FadeIn(index: i++, child: w);
    final name = app.prefs.displayName?.isNotEmpty == true ? ', ${app.prefs.displayName}' : '';

    return Scaffold(
      bottomNavigationBar: HomeActionBar(onQuickAdd: () => openQuickAdd(context)),
      body: RefreshIndicator(
        onRefresh: () async {
          app.refreshHomeClover();
          await app.sync?.sync();
        },
        child: PageBody(children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PixelText('Hey$name!', size: context.wide ? 28 : 22, shadow: context.cs.primary.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.calendar_month_rounded, size: 18, color: context.cs.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          overflow: TextOverflow.ellipsis,
                          daysToPay == null
                              ? 'No payday set'
                              : daysToPay == 0
                                  ? 'Payday today!'
                                  : 'Payday in $daysToPay day${daysToPay == 1 ? '' : 's'}',
                          style: context.tt.titleSmall?.copyWith(color: context.cs.onSurfaceVariant)),
                      ),
                    ]),
                  ]),
                ),
                IconButton(tooltip: 'Customize home', icon: const Icon(Icons.dashboard_customize_rounded), onPressed: () => _customize(context, hidden)),
                if (!context.wide) IconButton(tooltip: 'Settings', onPressed: () => Shell.go(context, 6), icon: const Icon(Icons.settings_rounded)),
              ]),
            ),
          ),
          if (show('clover'))
            enter(CloverHero(
              says: says,
              subtitles: app.prefs.subtitles,
              onTap: app.refreshHomeClover,
              onReplay: () => app.speak(says, force: true),
              talking: app.talking,
            )),
          if (show('available')) ...[
            const SizedBox(height: 12),
            enter(Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), side: BorderSide(color: context.cs.primary.withValues(alpha: 0.7), width: 1.5)),
              child: Stack(children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [context.cs.primary.withValues(alpha: 0.10), context.cs.primary.withValues(alpha: 0.22)]),
                    ),
                  ),
                ),
                Positioned.fill(child: ExcludeSemantics(child: NightScene(tint: context.cs.primary))),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Accents.savings, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Safe to Spend', style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: Accents.savings)),
                          Text('Spare money, yours to spend', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Money(d.availableToSpend, size: context.wide ? 52 : 44, color: d.availableToSpend < 0 ? Accents.danger : Accents.savings),
                    ),
                    Text(
                      '≈ ${m(d.dailySafeSpend)}/day (${d.daysUntilHorizon} day${d.daysUntilHorizon == 1 ? '' : 's'} left)'
                      '${payday != null ? ' · payday ${prettyDate(payday)}' : ' · no payday set (14-day window)'}',
                      style: context.tt.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                        '${m(d.totalMoney)} total = ${m(d.totalSaved)} saved + ${m(d.reservedForBills)} bills before payday + '
                        '${m(d.budgetedRemaining)} in budgets + ${m(d.availableToSpend)} free',
                        style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
                    if (d.availableToSpend < 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('You\'re ${m(-d.availableToSpend)} over: lower a budget, take some out of savings, or skip a bill. Tap "Bills Reserved" or a budget below.',
                            style: const TextStyle(color: Accents.danger, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final s in d.categoryStatuses.where((s) => s.hasLimit || s.extra != 0))
                        ActionChip(
                          avatar: CatDot(s.category, size: 12),
                          label: Text('${s.category.name} ${m(s.remaining)} left'),
                          onPressed: () => openQuickAdd(context, categoryId: s.category.id),
                        ),
                    ]),
                  ]),
                ),
              ]),
            )),
          ],
          if (show('stats')) ...[
            const SizedBox(height: 12),
            enter(GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: grid, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 112),
              children: [
                Stat('Total Money', d.totalMoney, icon: Icons.layers_rounded,
                    hint: '${m(d.totalMoney - d.totalSaved)} not set aside', onTap: () => sheet(context, const CountMoneySheet())),
                Stat('Budgets', d.budgetedRemaining, icon: Icons.sports_esports_rounded, color: Accents.vacation,
                    hint: 'Left this week', onTap: () => Shell.go(context, 2)),
                Stat('Bills Reserved', d.reservedForBills, icon: Icons.event_note_rounded, color: Accents.warn,
                    hint: envelope > 0 ? '+ ${m(envelope)} in bill envelope' : 'Tap to see / change', onTap: () => sheet(context, const ReservedSheet())),
                Stat('Saved', d.totalSaved, icon: Icons.savings_rounded, color: Accents.savings,
                    hint: 'Vaults + bill envelope', onTap: () => Shell.go(context, 3)),
              ],
            )),
          ],
          if (show('week')) ...[
            const SizedBox(height: 12),
            enter(Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const PixelText('This Week', size: 14),
                  const Spacer(),
                  if (spentPct != null)
                    Text('${((1 - spentPct) * 100).round()}% left',
                        style: TextStyle(fontWeight: FontWeight.w800, color: spentPct > 0.9 ? Accents.warn : Accents.savings)),
                ]),
                const SizedBox(height: 10),
                PixelBar(spentPct == null ? 0 : 1 - spentPct, color: context.cs.primary, height: 12),
                const SizedBox(height: 8),
                Text('${m(d.weekTotals.income)} income · ${m(d.weekTotals.netSpent)} spent · last week ${m(d.lastWeekTotals.netSpent)} spent',
                    style: context.tt.bodyMedium),
              ]),
            )),
          ],
          if (show('budgets')) ...[
            Section('Budgets this week', trailing: TextButton(onPressed: () => Shell.go(context, 2), child: const Text('All'))),
            enter(const BudgetsCard()),
          ],
          if (show('actions')) ...[
            const Section('Quick actions'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  avatar: const Icon(Icons.calculate_rounded),
                  label: const Text('Count my money'),
                  onPressed: () => sheet(context, const CountMoneySheet())),
              ActionChip(
                  avatar: const Icon(Icons.shopping_cart_checkout_rounded, color: Accents.savings),
                  label: const Text('Can I afford it?'),
                  onPressed: () => sheet(context, const AffordSheet())),
              ActionChip(
                  avatar: const Icon(Icons.mail_rounded, color: Accents.warn),
                  label: const Text('Bill envelope'),
                  onPressed: () => sheet(context, const BillEnvelopeSheet())),
              ActionChip(avatar: const Icon(Icons.remove_circle_outline), label: const Text('Expense'), onPressed: () => openQuickAdd(context)),
              ActionChip(avatar: const Icon(Icons.payments_outlined), label: const Text('Payday'), onPressed: () => openQuickAdd(context, kind: 'income')),
              ActionChip(
                  avatar: const Icon(Icons.auto_awesome, color: Accents.income),
                  label: const Text('Extra money'),
                  onPressed: () => d.accounts.isEmpty ? context.toast('Add an account first.') : sheet(context, const ExtraMoneySheet())),
              ActionChip(avatar: const Icon(Icons.swap_horiz), label: const Text('Transfer'), onPressed: () => openQuickAdd(context, kind: 'transfer')),
              ActionChip(
                  avatar: const Icon(Icons.auto_graph_rounded, color: Accents.savings),
                  label: const Text('Weekly plan'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyPlanScreen()))),
            ]),
          ],
          LayoutBuilder(builder: (context, box) {
            final upcomingPanel = show('bills')
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Section('Upcoming', trailing: TextButton(onPressed: () => Shell.go(context, 4), child: const Text('All'))),
                    if (upcoming.isEmpty)
                      const Panel(child: Text('No bills due in the next 2 weeks.'))
                    else
                      Panel(padding: EdgeInsets.zero, child: Column(children: [for (final o in upcoming) OccurrenceTile(o)])),
                  ])
                : null;
            final goalsPanel = show('goals') && d.goalStatuses.isNotEmpty
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Section('Goals & Trips', trailing: TextButton(onPressed: () => Shell.go(context, 3), child: const Text('All'))),
                    for (final g in d.goalStatuses.take(3)) Padding(padding: const EdgeInsets.only(bottom: 10), child: GoalCard(g)),
                  ])
                : null;
            if (box.maxWidth >= 760 && upcomingPanel != null && goalsPanel != null) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: upcomingPanel),
                const SizedBox(width: 12),
                Expanded(child: goalsPanel),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?upcomingPanel, ?goalsPanel]);
          }),
          if (show('accounts')) ...[
            const Section('Accounts'),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final a in d.accounts.where((a) => !a.archived))
                  ListTile(
                    leading: Icon(accountIcon(a.kind), color: Color(a.color)),
                    title: Text(a.name),
                    trailing: Money(d.ledger.accountBalance(a.id)),
                  ),
                if (d.accounts.isEmpty) const ListTile(title: Text('No accounts yet. Add one in Settings.')),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _customize(BuildContext context, List<String> hidden) async {
    final app = context.appRead;
    final h = {...hidden};
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Home widgets'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in homeWidgets.entries)
              CheckboxListTile(
                value: !h.contains(e.key),
                title: Text(e.value),
                onChanged: (v) => set(() => v! ? h.remove(e.key) : h.add(e.key)),
              ),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
        ),
      ),
    );
    app.savePrefs((p) => p.clover['home_hidden'] = h.toList());
  }
}

String occLabel(BillOccurrence o) => switch (o.status) {
      OccStatus.overdue => 'Overdue',
      OccStatus.dueSoon => 'Due soon',
      OccStatus.partial => 'Partially paid',
      OccStatus.paid => 'Paid',
      OccStatus.skipped => 'Skipped',
      OccStatus.upcoming => 'Upcoming',
    };

/// Fades and slides a Home card in, slightly staggered.
class FadeIn extends StatelessWidget {
  final int index;
  final Widget child;
  const FadeIn({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 320 + index * 70),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: c)),
        child: child,
      );
}

/// Clover big on the left, pixel speech bubble on the right.
class CloverHero extends StatelessWidget {
  final CloverSays says;
  final bool subtitles;
  final VoidCallback? onReplay, onTap;
  final ValueListenable<bool>? talking;
  const CloverHero({super.key, required this.says, this.subtitles = true, this.onReplay, this.onTap, this.talking});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final big = context.wide;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      CloverSprite(mood: says.mood, size: big ? 150 : (MediaQuery.sizeOf(context).width < 360 ? 84 : 108), onTap: onTap, talking: talking),
      const SizedBox(width: 8),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c)),
          child: Container(
            key: ValueKey(says.lineId + says.text),
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: ShapeDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF15111F) : Colors.white,
              shape: PixelBorder(step: 4, width: 3, color: cs.onSurface.withValues(alpha: 0.85)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  PixelText('Clover - ${says.mood.label}', size: 9, color: cs.primary),
                  const SizedBox(height: 8),
                  Text(subtitles ? says.text : '(subtitles off)',
                      style: TextStyle(fontWeight: FontWeight.w600, height: 1.35, fontSize: big ? 18 : 15)),
                ]),
              ),
              if (onReplay != null) IconButton(tooltip: 'Replay', onPressed: onReplay, icon: const Icon(Icons.replay_rounded, size: 20)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Set Money · Quick Add · Give it a Job, pinned under the Home page.
class HomeActionBar extends StatelessWidget {
  final VoidCallback onQuickAdd;
  const HomeActionBar({super.key, required this.onQuickAdd});
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    return SafeArea(
      top: false,
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(children: [
              Expanded(
                child: narrow
                    ? Tooltip(
                        message: 'Set Money',
                        child: OutlinedButton(
                            onPressed: () => sheet(context, const CountMoneySheet()), style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                            child: const Icon(Icons.layers_rounded)))
                    : OutlinedButton.icon(
                        onPressed: () => sheet(context, const CountMoneySheet()),
                        icon: const Icon(Icons.layers_rounded),
                        label: const Text('Set Money', overflow: TextOverflow.ellipsis),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 56),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: const Color(0xFF6D4AE8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFB9A3FF), width: 1.5)),
                    textStyle: context.tt.titleMedium?.copyWith(fontSize: narrow ? 16 : 18, fontWeight: FontWeight.w800),
                  ),
                  onPressed: onQuickAdd,
                  icon: const Icon(Icons.add_rounded, size: 26),
                  label: const Text('Quick Add'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: narrow
                    ? Tooltip(
                        message: 'Give it a Job',
                        child: OutlinedButton(
                            onPressed: () => sheet(context, const GiveJobSheet()), style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                            child: const Icon(Icons.task_alt_rounded)))
                    : OutlinedButton.icon(
                        onPressed: () => sheet(context, const GiveJobSheet()),
                        icon: const Icon(Icons.task_alt_rounded),
                        label: const Text('Give it a Job', overflow: TextOverflow.ellipsis),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
