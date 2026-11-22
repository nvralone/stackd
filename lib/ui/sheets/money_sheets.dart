// Count my money (match the app to real balances) + add money to a budget.
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/finance.dart';
import '../common.dart';
import '../theme.dart';
import 'entry_sheet.dart';

/// Enter what is really in each account; differences are recorded as balance adjustments
/// (not income or spending), so every total in the app matches your real money.
class CountMoneySheet extends StatefulWidget {
  const CountMoneySheet({super.key});
  @override
  State<CountMoneySheet> createState() => _CountMoneySheetState();
}

class _CountMoneySheetState extends State<CountMoneySheet> {
  final ctl = <String, TextEditingController>{};

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final accts = d.accounts.where((a) => !a.archived).toList();
    for (final a in accts) {
      ctl.putIfAbsent(a.id, () => TextEditingController(text: centsToInput(d.ledger.accountBalance(a.id))));
    }
    var newTotal = 0;
    for (final a in accts) {
      newTotal += parseCents(ctl[a.id]!.text) ?? d.ledger.accountBalance(a.id);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Count my money', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Type what is really in each place right now: cash in your wallet, envelopes, Cash App, bank. '
            'Money already sitting in an envelope for a vault still counts here (vaults are just labels on it).', style: context.tt.bodySmall),
        const SizedBox(height: 12),
        for (final a in accts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(accountIcon(a.kind), color: Color(a.color)),
              const SizedBox(width: 10),
              Expanded(child: Text(a.name)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: ctl[a.id],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(prefixText: '\$ ', isDense: true, helperText: 'app: ${m(d.ledger.accountBalance(a.id))}'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ),
        const Divider(),
        Row(children: [const Expanded(child: Text('Total money')), Money(newTotal)]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final events = <LedgerEvent>[];
            for (final a in accts) {
              final real = parseCents(ctl[a.id]!.text);
              if (real == null) continue;
              final diff = real - d.ledger.accountBalance(a.id);
              if (diff != 0) events.add(app.event(kind: 'adjustment', amountCents: diff, accountId: a.id, note: 'Counted my money'));
            }
            if (events.isNotEmpty) app.record(events);
            Navigator.pop(context);
            context.toast(events.isEmpty ? 'Already matches.' : 'Balances updated to match your real money.');
          },
          child: const Text('Save balances'),
        ),
      ]),
    );
  }
}

Future<void> addToBudget(BuildContext context, Category c) async {
  final app = context.appRead;
  final ctl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (x) => AlertDialog(
      title: Text('Add money to ${c.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Raises ${c.name}\'s budget for this ${c.period == 'monthly' ? 'month' : 'week'} only. No money moves between accounts.'),
        const SizedBox(height: 10),
        TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ ')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Add')),
      ],
    ),
  );
  final cents = (parseCents(ctl.text) ?? 0).abs();
  if (ok != true || cents == 0) return;
  app.save(BudgetAllocation(
      id: newId(), categoryId: c.id, periodStart: periodOf(app.data.todayDate, c.period, app.prefs.weekStart).start,
      amountCents: cents, note: 'Added by hand'));
}

/// Home card: every budget with what's left, per-day pace, and quick buttons.
class BudgetsCard extends StatelessWidget {
  const BudgetsCard({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final list = d.categoryStatuses.where((s) => s.hasLimit || s.extra > 0).toList();
    if (list.isEmpty) {
      return const Panel(child: Text('No budgets yet. Set a limit on a category in Budget, or use Weekly plan.'));
    }
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        for (final s in list) _row(context, d, s),
      ]),
    );
  }

  Widget _row(BuildContext context, FinanceData d, CategoryStatus s) {
    final c = s.category;
    final end = periodOf(d.todayDate, c.period, d.weekStart).end;
    final daysLeft = daysBetween(d.todayDate, end).clamp(1, 31);
    final perDay = s.remaining <= 0 ? 0 : s.remaining ~/ daysLeft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Column(children: [
        Row(children: [
          CatDot(c, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${m(s.remaining)} left of ${m(s.budget)} · ${m(perDay)}/day for $daysLeft day${daysLeft == 1 ? '' : 's'}',
                  style: context.tt.bodySmall?.copyWith(color: s.remaining < 0 ? Accents.danger : null)),
            ]),
          ),
          IconButton(tooltip: 'I spent', icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: () => openQuickAdd(context, categoryId: c.id)),
          IconButton(tooltip: 'Add money to this budget', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => addToBudget(context, c)),
        ]),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.only(right: 8), child: Bar(s.spent, s.budget, color: Color(c.color), height: 6)),
      ]),
    );
  }
}
