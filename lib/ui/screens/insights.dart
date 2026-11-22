import 'package:material_ui/material_ui.dart';

import '../../clover/clover_widget.dart';
import '../../core/dates.dart';
import '../../domain/insights.dart';
import '../app.dart';
import '../charts.dart';
import '../common.dart';
import '../theme.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool monthly = false;

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final series = monthly ? monthlySeries(d) : weeklySeries(d);
    final range = monthly
        ? (start: monthStartOf(d.todayDate), end: addMonths(monthStartOf(d.todayDate), 1))
        : d.thisWeek;
    final cats = categoryBreakdown(d, range.start, range.end);
    final totals = d.ledger.totals(range.start, range.end);
    final ff = fastFood(d);
    final ideas = reductionIdeas(d);
    final recurring = recurringMonthly(d);
    final over = d.categoryStatuses.where((c) => c.over).toList();
    return Scaffold(
      appBar: const PageBar('Insights'),
      body: PageBody(children: [
        Panel(
          color: context.cs.primary.withValues(alpha: 0.12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecapScreen())),
          child: const Row(children: [
            Icon(Icons.movie_filter_rounded),
            SizedBox(width: 10),
            Expanded(child: Text('Weekly recap with Clover', style: TextStyle(fontWeight: FontWeight.w800))),
            Icon(Icons.chevron_right_rounded),
          ]),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Weekly')), ButtonSegment(value: true, label: Text('Monthly'))],
          selected: {monthly},
          onSelectionChanged: (v) => setState(() => monthly = v.first),
        ),
        const Section('Income vs spending'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 170,
              child: BarChart(
                series: [[for (final p in series) p.income], [for (final p in series) p.spent], [for (final p in series) p.saved.clamp(0, 1 << 40)]],
                colors: const [Accents.income, Accents.danger, Accents.savings],
                labels: [for (final p in series) monthly ? monthNames[p.start.month - 1] : prettyDate(p.start)],
              ),
            ),
            const SizedBox(height: 8),
            const Wrap(spacing: 12, children: [_Legend('Income', Accents.income), _Legend('Spent', Accents.danger), _Legend('Saved', Accents.savings)]),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Stat(monthly ? 'Spent this month' : 'Spent this week', totals.netSpent)),
          const SizedBox(width: 12),
          Expanded(child: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Savings rate', style: context.tt.labelMedium),
            Text(totals.income == 0 ? '—' : '${totals.savingsRate}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Accents.savings)),
            Text('of earned income', style: context.tt.bodySmall),
          ]))),
        ]),
        Section('By category ${monthly ? '(this month vs last)' : '(this week vs last)'}'),
        if (cats.isEmpty) const Panel(child: Text('No spending recorded in this period.')),
        if (cats.isNotEmpty)
          Panel(
            child: Column(children: [
              for (final s in cats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Row(children: [
                      if (s.category != null) CatDot(s.category!, size: 16) else const Icon(Icons.help_outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.category?.name ?? 'Uncategorized')),
                      Text(pctChange(s.cents, s.previous), style: TextStyle(color: s.change > 0 ? Accents.danger : Accents.savings, fontSize: 12)),
                      const SizedBox(width: 10),
                      Money(s.cents, size: 14),
                    ]),
                    const SizedBox(height: 4),
                    Bar(s.cents, cats.first.cents, color: Color(s.category?.color ?? 0xFF90A4AE), height: 6),
                  ]),
                ),
            ]),
          ),
        const Section('Fast food'),
        Panel(
          child: d.categoryByTag('fast_food') == null
              ? const Text('No Fast Food category (tag) found.')
              : Text('${m(ff.total)} this week over ${ff.visits} visit${ff.visits == 1 ? '' : 's'} · last week ${m(ff.previousTotal)} (${pctChange(ff.total, ff.previousTotal)})'),
        ),
        if (over.isNotEmpty) ...[
          const Section('Over budget'),
          for (final c in over)
            Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(leading: CatDot(c.category), title: Text(c.category.name), trailing: Money(-c.remaining, color: Accents.danger))),
        ],
        const Section('Where you could cut back'),
        Text('Suggestions only. Categories above their 4-week average this week.', style: context.tt.bodySmall),
        const SizedBox(height: 6),
        if (ideas.isEmpty) const Panel(child: Text('Nothing stands out. Spending is at or below your usual pace.')),
        for (final i in ideas.take(5))
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: CatDot(i.category),
              title: Text(i.category.name),
              subtitle: Text('${m(i.currentWeekly)} this week vs ~${m(i.typicalWeekly)} usual'),
              trailing: Text('save ~${m(i.possibleSaving)}', style: const TextStyle(color: Accents.savings, fontWeight: FontWeight.w700)),
            ),
          ),
        const Section('Recurring costs (monthly equivalent)'),
        if (recurring.isEmpty) const Panel(child: Text('No recurring bills yet.')),
        if (recurring.isNotEmpty)
          Panel(
            child: Column(children: [
              for (final r in recurring) Row(children: [Expanded(child: Text(r.$1.name)), Money(r.$2, size: 14)]),
              const Divider(),
              Row(children: [const Expanded(child: Text('Total / month', style: TextStyle(fontWeight: FontWeight.w800))), Money(recurring.fold(0, (s, r) => s + r.$2))]),
            ]),
          ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  const _Legend(this.label, this.color);
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, color: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 12))]);
}

class RecapScreen extends StatefulWidget {
  const RecapScreen({super.key});
  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen> {
  int weeksBack = 1;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final start = addDays(d.thisWeek.start, -7 * weeksBack);
    final r = buildRecap(d, weekStartDate: start);
    final says = app.brain.recap(d, r);
    final narration = [
      says.text,
      'Income ${m(r.totals.income)}. Spent ${m(r.totals.netSpent)}. Saved ${m(r.totals.netSaved)}.',
      if (r.overBudget.isNotEmpty) '${r.overBudget.length} categor${r.overBudget.length == 1 ? 'y' : 'ies'} went over budget.',
      if (r.billsNext7 > 0) 'Bills coming up this week: ${m(r.billsNext7)}.',
    ].join(' ');
    Widget line(String k, int v, {Color? c, int? prev}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(k)),
            if (prev != null) Text('${pctChange(v, prev)}  ', style: context.tt.bodySmall),
            Money(v, size: 15, color: c),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly recap')),
      body: PageBody(children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => weeksBack++), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${prettyDate(r.start)} – ${prettyDate(addDays(r.end, -1))}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(onPressed: weeksBack <= 0 ? null : () => setState(() => weeksBack--), icon: const Icon(Icons.chevron_right)),
        ]),
        Panel(
          child: Column(children: [
            CloverSprite(mood: says.mood, size: 140, talking: app.talking, onTap: () => app.speak(says, force: true)),
            const SizedBox(height: 8),
            if (app.prefs.subtitles) Text(says.text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(onPressed: () => app.speak(says, force: true), icon: const Icon(Icons.graphic_eq_rounded), label: const Text('Clover reacts')),
              FilledButton.tonalIcon(
                onPressed: () => app.speak(says.copyText(narration), narrate: true, force: true),
                icon: const Icon(Icons.record_voice_over_rounded),
                label: const Text('Narrate recap'),
              ),
              IconButton(tooltip: 'Stop', onPressed: () => app.voice?.stop(), icon: const Icon(Icons.stop_rounded)),
            ]),
          ]),
        ),
        const Section('The numbers'),
        Panel(
          child: Column(children: [
            line('Income received', r.totals.income, c: Accents.income, prev: r.previous.income),
            line('Money spent', r.totals.netSpent, prev: r.previous.netSpent),
            line('Money saved (net)', r.totals.netSaved, c: Accents.savings, prev: r.previous.netSaved),
            if (r.totals.refunds > 0) line('Refunds', r.totals.refunds),
            if (r.emergencyWithdrawals > 0) line('Emergency withdrawals', r.emergencyWithdrawals),
            if (r.otherWithdrawals > 0) line('Other savings withdrawals', r.otherWithdrawals, c: Accents.warn),
            line('Bills due next 7 days', r.billsNext7),
          ]),
        ),
        const Section('Category breakdown'),
        if (r.categories.isEmpty) const Panel(child: Text('No spending recorded.')),
        for (final c in r.categories.take(8))
          ListTile(
            dense: true,
            leading: c.category == null ? null : CatDot(c.category!, size: 14),
            title: Text(c.category?.name ?? 'Uncategorized'),
            subtitle: Text('previous week ${m(c.previous)}'),
            trailing: Money(c.cents, size: 14),
          ),
        if (r.overBudget.isNotEmpty) ...[
          const Section('Budget performance'),
          for (final c in r.overBudget) ListTile(dense: true, title: Text('${c.category.name} over by'), trailing: Money(-c.remaining, size: 14, color: Accents.danger)),
        ],
        if (r.vacations.isNotEmpty) ...[
          const Section('Vacation progress'),
          for (final v in r.vacations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${v.goal.name} · ${v.pct}%'),
                const SizedBox(height: 6),
                Bar(v.saved, v.goal.goalCents, color: Accents.vacation),
              ])),
            ),
        ],
      ]),
    );
  }
}
