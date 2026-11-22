// Forecast + What-If. Simulations never write data.
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/forecast.dart';
import '../charts.dart';
import '../common.dart';
import '../theme.dart';
import 'budget.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});
  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  final spend = TextEditingController(), save = TextEditingController(), bill = TextEditingController(), extra = TextEditingController();
  bool reduce = true;
  String? goalId;
  int shiftDays = 0;
  int weeks = 8;

  Scenario get scenario => Scenario(
        weeklySpendDelta: (parseCents(spend.text) ?? 0).abs() * (reduce ? -1 : 1),
        extraSavingPerPayday: (parseCents(save.text) ?? 0).abs(),
        newMonthlyBill: (parseCents(bill.text) ?? 0).abs(),
        oneTimeIncome: (parseCents(extra.text) ?? 0).abs(),
        goalId: goalId,
        goalDateShiftDays: shiftDays,
      );

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final base = buildForecast(d, weeks: weeks);
    final s = scenario;
    final sim = buildForecast(d, weeks: weeks, s: s);
    Widget field(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: '\$ ', isDense: true),
          onChanged: (_) => setState(() {}),
        );
    Widget cmp(String label, int a, int b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label)),
            Money(a, size: 14),
            if (!s.isEmpty) ...[
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 14)),
              Money(b, size: 14, color: b > a ? Accents.savings : (b < a ? Accents.danger : null)),
            ],
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Forecast & What-If')),
      body: PageBody(children: [
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 4, label: Text('4 weeks')), ButtonSegment(value: 8, label: Text('8 weeks'))],
          selected: {weeks},
          onSelectionChanged: (v) => setState(() => weeks = v.first),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Projected free money', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              BufferChip(s.isEmpty ? base.bufferStatus : sim.bufferStatus),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: LineChart(
                series: [
                  [for (final p in base.weekly) p.free],
                  if (!s.isEmpty) [for (final p in sim.weekly) p.free],
                ],
                colors: [context.cs.primary, Accents.income],
                labels: [for (final p in base.weekly) prettyDate(p.date)],
              ),
            ),
            if (!s.isEmpty) Text('Purple: current path · Yellow: what-if', style: context.tt.bodySmall),
          ]),
        ),
        const Section('Actual vs projected'),
        Panel(
          child: Column(children: [
            cmp('Actual money now', d.totalMoney, d.totalMoney),
            cmp('Saved in vaults (actual)', d.totalSaved, d.totalSaved),
            cmp('Scheduled bills in window', base.scheduledBills, sim.scheduledBills),
            cmp('Expected income (assumption)', base.expectedIncome, sim.expectedIncome),
            cmp('Spending pace per week (assumption)', base.weeklySpendAssumed, sim.weeklySpendAssumed),
            const Divider(),
            cmp('Balance before next payday', base.balanceAtPayday, sim.balanceAtPayday),
            cmp('Balance in 4 weeks', base.at(4).balance, sim.at(4).balance),
            if (weeks == 8) cmp('Balance in 8 weeks', base.at(8).balance, sim.at(8).balance),
            cmp('Daily allowance', base.dailyAllowance, sim.dailyAllowance),
            cmp('Lowest free money', base.lowestFree, sim.lowestFree),
          ]),
        ),
        const Section('What if...'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: field(spend, 'Change weekly spending by')),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('Less')), ButtonSegment(value: false, label: Text('More'))],
                selected: {reduce},
                onSelectionChanged: (v) => setState(() => reduce = v.first),
              ),
            ]),
            const SizedBox(height: 10),
            field(save, 'Save more each payday'),
            const SizedBox(height: 10),
            field(bill, 'Add a monthly bill'),
            const SizedBox(height: 10),
            field(extra, 'Receive extra money once'),
            const SizedBox(height: 10),
            if (d.goals.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: goalId,
                decoration: const InputDecoration(labelText: 'Goal to focus (extra savings / date move)', isDense: true),
                items: [const DropdownMenuItem(value: null, child: Text('All goals')), for (final g in d.goals) DropdownMenuItem(value: g.id, child: Text(g.name))],
                onChanged: (v) => setState(() => goalId = v),
              ),
              if (goalId != null && d.goal(goalId)?.targetDate != null) ...[
                const SizedBox(height: 8),
                Text('Move target date: ${shiftDays >= 0 ? '+' : ''}$shiftDays days'),
                Slider(value: shiftDays.toDouble(), min: -90, max: 180, divisions: 54, label: '$shiftDays d', onChanged: (v) => setState(() => shiftDays = v.round())),
              ],
            ],
            TextButton(
              onPressed: () => setState(() {
                for (final c in [spend, save, bill, extra]) {
                  c.clear();
                }
                shiftDays = 0;
              }),
              child: const Text('Reset scenario'),
            ),
            Text('Simulations never change your real records.', style: context.tt.bodySmall),
          ]),
        ),
        if (d.goalStatuses.isNotEmpty) ...[
          const Section('Goal completion'),
          Panel(
            child: Column(children: [
              for (final g in d.goalStatuses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(g.goal.name)),
                    Text(_date(base.goalCompletion[g.goal.id])),
                    if (!s.isEmpty) ...[
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 14)),
                      Text(_date(sim.goalCompletion[g.goal.id]), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
              for (final e in sim.goalNeededPerWeek.entries)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${d.goal(e.key)?.name}: needs ${m(e.value)}/week to hit its target date', style: context.tt.bodySmall),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  String _date(DateTime? d) => d == null ? 'No pace yet' : '${prettyDate(d)} ${d.year}';
}
