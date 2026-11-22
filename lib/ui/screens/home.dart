import 'package:material_ui/material_ui.dart';

import '../../clover/clover_widget.dart';
import '../../core/dates.dart';
import '../../domain/bills.dart';
import '../app.dart';
import '../common.dart';
import '../sheets/entry_sheet.dart';
import '../theme.dart';
import 'bills.dart';
import 'goals.dart';
import 'plan.dart';

const homeWidgets = {
  'clover': 'Clover',
  'available': 'Safe to spend',
  'stats': 'Money overview',
  'week': 'This week',
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

    return Scaffold(
      appBar: PageBar('Hey${app.prefs.displayName?.isNotEmpty == true ? ', ${app.prefs.displayName}' : ''}', actions: [
        IconButton(tooltip: 'Customize home', icon: const Icon(Icons.dashboard_customize_rounded), onPressed: () => _customize(context, hidden)),
      ]),
      body: RefreshIndicator(
        onRefresh: () async {
          app.refreshHomeClover();
          await app.sync?.sync();
        },
        child: PageBody(children: [
          if (show('clover'))
            Panel(
              child: CloverCard(
                says: says,
                subtitles: app.prefs.subtitles,
                onTap: app.refreshHomeClover,
                onReplay: () => app.speak(says, force: true),
                talking: app.talking,
              ),
            ),
          if (show('available')) ...[
            const SizedBox(height: 12),
            Panel(
              color: context.cs.primary.withValues(alpha: 0.12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SAFE TO SPEND', style: context.tt.labelMedium?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Money(d.availableToSpend, size: 40, color: d.availableToSpend < 0 ? Accents.danger : null),
                ),
                const SizedBox(height: 4),
                Text(
                  '${m(d.dailySafeSpend)} per day for ${d.daysUntilHorizon} day${d.daysUntilHorizon == 1 ? '' : 's'}'
                  '${d.nextPayday != null ? ' · payday ${prettyDate(d.nextPayday!)}' : ' · no payday set (14-day window)'}',
                  style: context.tt.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text('Total money − saved vaults − bills due before payday. Projections are not balances.',
                    style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
              ]),
            ),
          ],
          if (show('stats')) ...[
            const SizedBox(height: 12),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: grid, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 92),
              children: [
                Stat('Total money', d.totalMoney, icon: Icons.account_balance_wallet_rounded),
                Stat('Reserved for bills', d.reservedForBills, icon: Icons.event_note_rounded, color: Accents.warn, onTap: () => Shell.go(context, 4)),
                Stat('Saved in vaults', d.totalSaved, icon: Icons.savings_rounded, color: Accents.savings, onTap: () => Shell.go(context, 3)),
                Stat('Vacation savings', d.vacationSaved, icon: Icons.flight_takeoff_rounded, color: Accents.vacation, onTap: () => Shell.go(context, 3)),
              ],
            ),
          ],
          if (show('week')) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Stat('Income this week', d.weekTotals.income, icon: Icons.trending_up_rounded, color: Accents.income)),
              const SizedBox(width: 12),
              Expanded(child: Stat('Spent this week', d.weekTotals.netSpent, icon: Icons.trending_down_rounded,
                  hint: 'Last week ${m(d.lastWeekTotals.netSpent)}')),
            ]),
          ],
          if (show('actions')) ...[
            const Section('Quick actions'),
            Wrap(spacing: 8, runSpacing: 8, children: [
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
          if (show('bills')) ...[
            Section('Upcoming bills', trailing: TextButton(onPressed: () => Shell.go(context, 4), child: const Text('All'))),
            if (upcoming.isEmpty)
              const Panel(child: Text('No bills due in the next 2 weeks.'))
            else
              Panel(
                padding: EdgeInsets.zero,
                child: Column(children: [for (final o in upcoming) OccurrenceTile(o)]),
              ),
          ],
          if (show('goals') && d.goalStatuses.isNotEmpty) ...[
            Section('Savings progress', trailing: TextButton(onPressed: () => Shell.go(context, 3), child: const Text('All'))),
            for (final g in d.goalStatuses.take(3)) Padding(padding: const EdgeInsets.only(bottom: 10), child: GoalCard(g)),
          ],
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
