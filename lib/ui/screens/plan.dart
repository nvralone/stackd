import 'package:material_ui/material_ui.dart';

import '../../domain/plan.dart';
import '../common.dart';
import '../theme.dart';

/// "How much should go where each week" — a recommendation built from bills, goals and budgets.
class WeeklyPlanScreen extends StatelessWidget {
  const WeeklyPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final p = buildWeeklyPlan(d);
    final sections = [
      (PlanKind.bill, 'Bills & debts', Icons.event_note_rounded, Accents.warn),
      (PlanKind.essential, 'Essentials', Icons.shopping_cart_rounded, context.cs.primary),
      (PlanKind.goal, 'Savings goals', Icons.savings_rounded, Accents.savings),
      (PlanKind.spending, 'Spending', Icons.pie_chart_rounded, Accents.vacationBlue),
      (PlanKind.buffer, 'Left over', Icons.account_balance_wallet_rounded, Accents.income),
    ];
    final changes = p.lines.where((l) => (l.kind == PlanKind.goal || l.kind == PlanKind.spending || l.kind == PlanKind.essential) && l.weekly != l.current).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly plan')),
      body: PageBody(children: [
        Panel(
          color: context.cs.primary.withValues(alpha: 0.12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EACH WEEK YOU BRING IN ABOUT', style: context.tt.labelMedium?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            Money(p.income, size: 32, color: Accents.income),
            Text('Based on ${p.incomeSource}. A suggestion only; nothing changes unless you apply it.', style: context.tt.bodySmall),
            if (p.income == 0)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Add a payday in Budget → Paydays (or log some income) so the plan has something to split.')),
          ]),
        ),
        if (p.shortfall > 0) ...[
          const SizedBox(height: 10),
          Panel(
            color: Accents.danger.withValues(alpha: 0.15),
            child: Text('Bills and essentials cost ${m(p.shortfall)} more per week than you bring in. Goals and spending are set to \$0 until that gap closes.'),
          ),
        ],
        for (final (kind, title, icon, color) in sections)
          if (p.of(kind).isNotEmpty) ...[
            Section(title, trailing: Money(p.total(kind), size: 15, color: color)),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final l in p.of(kind))
                  ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(l.name),
                    subtitle: Text(l.why + (l.current > 0 && l.current != l.weekly ? ' · now ${m(l.current)}/wk' : '')),
                    trailing: Text('${m(l.weekly)}/wk', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
          ],
        const SizedBox(height: 16),
        if (changes.isNotEmpty)
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded),
            label: Text('Use these amounts (${changes.length} change${changes.length == 1 ? '' : 's'})'),
            onPressed: () async {
              final summary = changes.map((l) => '${l.name}: ${m(l.current)} → ${m(l.weekly)} /wk').join('\n');
              if (!await confirm(context, 'Update your budget?',
                  'Category limits and goal contributions will be set to:\n\n$summary\n\nBills are not changed. No money moves.', ok: 'Apply')) {
                return;
              }
              for (final l in changes) {
                if (l.kind == PlanKind.goal) {
                  final g = d.goal(l.id);
                  if (g != null) {
                    app.save(g
                      ..contributionCents = l.weekly
                      ..contributionFreq = 'weekly');
                  }
                } else {
                  final c = d.category(l.id);
                  if (c != null) app.save(c..limitCents = limitForPeriod(l.weekly, c.period));
                }
              }
              if (context.mounted) context.toast('Budget updated.');
            },
          ),
        const SizedBox(height: 8),
        Text('How it works: bills and essentials come first, then goals (enough to hit target dates) and your spending limits. '
            'If there isn\'t enough, goals and spending shrink evenly. Extra money is split half to goals, half kept free.',
            style: context.tt.bodySmall),
      ]),
    );
  }
}
