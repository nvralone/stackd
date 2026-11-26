// Count my money (match the app to real balances) + add money to a budget.
import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/allocation.dart';
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
      ctl.putIfAbsent(a.id, () => TextEditingController(text: centsToInput(d.accountSpendable(a.id))));
    }
    var newTotal = 0;
    for (final a in accts) {
      newTotal += parseCents(ctl[a.id]!.text) ?? d.accountSpendable(a.id);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Count my money', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Only for fixing a balance that is wrong. To add a paycheck or extra money, use Quick Add > Income instead, or it counts twice. '
            'Type what is really in each place right now: cash in your wallet, envelopes, Cash App, bank. '
            "Don't include your savings: vaults and the Bill envelope (${m(d.totalSaved)}) are kept separately and stay as they are.", style: context.tt.bodySmall),
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
                  decoration: InputDecoration(prefixText: '\$ ', isDense: true, helperText: 'app: ${m(d.accountSpendable(a.id))}'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ),
        const Divider(),
        Row(children: [const Expanded(child: Text('Money in your accounts')), Money(newTotal)]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final events = <LedgerEvent>[];
            for (final a in accts) {
              final real = parseCents(ctl[a.id]!.text);
              if (real == null) continue;
              final diff = real - d.accountSpendable(a.id); // savings parked in the account are kept
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

/// The envelope for bills that build up (monthly insurance, subscriptions...). Add from spare money or
/// new cash, with a recommended amount; take money back out any time.
class BillEnvelopeSheet extends StatefulWidget {
  const BillEnvelopeSheet({super.key});
  @override
  State<BillEnvelopeSheet> createState() => _BillEnvelopeSheetState();
}

class _BillEnvelopeSheetState extends State<BillEnvelopeSheet> {
  late final amount = TextEditingController(text: () {
    final need = billSavingsNeed(context.appRead.data);
    return need > 0 ? centsToInput(need) : '';
  }());

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final env = d.goals.where((g) => g.name == billSavingsName && !g.archived).firstOrNull;
    final saved = env == null ? 0 : d.ledger.goalBalance(env.id);
    final later = laterBills(d);
    final need = billSavingsNeed(d);
    final cents = (parseCents(amount.text) ?? 0).abs();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Bill envelope', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Money set aside for bills that come later. It is taken out of your spare money and kept here until you pay them.',
            style: context.tt.bodySmall),
        const SizedBox(height: 12),
        Panel(
          color: Accents.warn.withValues(alpha: 0.12),
          child: Row(children: [
            const Icon(Icons.mail_rounded, color: Accents.warn),
            const SizedBox(width: 10),
            Expanded(child: Text('In the envelope', style: context.tt.titleSmall)),
            Money(saved, size: 22, color: Accents.warn),
          ]),
        ),
        if (d.billEnvelopeUnassigned > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${m(d.billEnvelopeUnassigned)} of it is not set aside for a specific bill yet. You can assign it when you split a paycheck.',
                style: context.tt.bodySmall),
          ),
        const Section('Coming up'),
        if (later.isEmpty) const Text('No later bills in the next 3 months.'),
        for (final l in later)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l.name),
            subtitle: Text('${m(l.amount - l.paid)} due ${prettyDate(l.due)} · ${m(l.inEnvelope)} set aside · ${l.paychecksLeft} paycheck${l.paychecksLeft == 1 ? '' : 's'} left'),
            trailing: Text(l.recommended > 0 ? '${m(l.recommended)} now' : 'on track', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        if (cents > 0 && later.isNotEmpty)
          Text('Adding ${m(cents)} sets aside: ${envelopeSplit(d, cents).entries.map((e) => '${e.key == null ? 'unassigned' : d.bill(e.key)?.name} ${m(e.value)}').join(', ')}',
              style: context.tt.bodySmall),
        const SizedBox(height: 8),
        Text(need > 0 ? 'Recommended to add now: ${m(need)}' : 'You are on track. Nothing needed right now.',
            style: TextStyle(fontWeight: FontWeight.w800, color: need > 0 ? Accents.warn : Accents.savings)),
        Text('Spare money right now: ${m(d.availableToSpend)}', style: context.tt.bodySmall),
        const SizedBox(height: 12),
        AmountField(amount, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: cents == 0
              ? null
              : () {
                  app.addToBillEnvelope(cents);
                  Navigator.pop(context);
                  context.toast('Moved ${m(cents)} from spare money into the bill envelope.');
                },
          icon: const Icon(Icons.south_rounded),
          label: const Text('Add from my spare money'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: cents == 0
              ? null
              : () {
                  app.addToBillEnvelope(cents, newCash: true);
                  Navigator.pop(context);
                  context.toast('Added ${m(cents)} cash to the bill envelope. Spare money unchanged.');
                },
          icon: const Icon(Icons.add_card_rounded),
          label: const Text('Add new cash I have (not in the app yet)'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: cents == 0 || saved == 0
              ? null
              : () async {
                  final take = cents > saved ? saved : cents;
                  if (take > d.billEnvelopeUnassigned &&
                      !await confirm(context, 'Take out bill money?',
                          'Only ${m(d.billEnvelopeUnassigned)} is unassigned. Taking ${m(take)} uses money set aside for your bills (the bill due last loses it first).')) {
                    return;
                  }
                  app.takeFromBillEnvelope(take);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  context.toast('Moved ${m(take)} back to spare money.');
                },
          icon: const Icon(Icons.north_rounded),
          label: const Text('Take out (back to spare money)'),
        ),
        const SizedBox(height: 4),
        Text('When you pay one of these bills, tick "Use my Bill savings" and it comes out of this envelope.', style: context.tt.bodySmall),
      ]),
    );
  }
}

/// Give free money a job: put it in a budget, save it in a vault, or move it to another account.
class GiveJobSheet extends StatefulWidget {
  const GiveJobSheet({super.key});
  @override
  State<GiveJobSheet> createState() => _GiveJobSheetState();
}

class _GiveJobSheetState extends State<GiveJobSheet> {
  String where = 'budget';
  final amount = TextEditingController();
  String? target, from, to;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final cents = (parseCents(amount.text) ?? 0).abs();
    final accts = d.accounts.where((a) => !a.archived).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Give your money a job', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Free right now: ${m(d.availableToSpend)}', style: context.tt.bodyMedium),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'budget', label: Text('Budget')),
            ButtonSegment(value: 'vault', label: Text('Vault')),
            ButtonSegment(value: 'bills', label: Text('Bills')),
            ButtonSegment(value: 'account', label: Text('Account')),
          ],
          selected: {where},
          onSelectionChanged: (s) => setState(() {
            where = s.first;
            target = null;
          }),
        ),
        const SizedBox(height: 12),
        AmountField(amount, autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        if (where == 'bills')
          Text('Goes into your Bill envelope. Recommended now: ${m(billSavingsNeed(d))}.', style: context.tt.bodyMedium)
        else if (where == 'budget')
          CategoryPicker(value: target, onChanged: (v) => setState(() => target = v))
        else if (where == 'vault')
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: target,
            decoration: const InputDecoration(labelText: 'Vault'),
            items: [for (final g in d.goals.where((g) => !g.archived)) DropdownMenuItem(value: g.id, child: Text(g.name))],
            onChanged: (v) => setState(() => target = v),
          )
        else ...[
          AccountPicker(value: from, label: 'From account', onChanged: (v) => setState(() => from = v)),
          const SizedBox(height: 12),
          AccountPicker(value: to, label: 'To account', exclude: from, onChanged: (v) => setState(() => to = v)),
        ],
        const SizedBox(height: 8),
        Text(
          switch (where) {
            'budget' => 'Adds to that budget for this period. The money stays where it is; it just has a job now.',
            'vault' => 'Sets it aside in the vault. It still counts in your total money, but not as free money.',
            'bills' => 'Saved for bills that come later (monthly insurance, subscriptions). Use it when you pay them.',
            _ => 'Moves money between your accounts (e.g. cash to Cash App). Not income or spending.',
          },
          style: context.tt.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: cents == 0 || (where == 'account' ? (from == null || to == null) : (where != 'bills' && target == null))
              ? null
              : () {
                  if (where == 'bills') {
                    app.addToBillEnvelope(cents);
                  } else if (where == 'budget') {
                    final c = d.category(target)!;
                    app.save(BudgetAllocation(
                        id: newId(), categoryId: c.id, periodStart: periodOf(d.todayDate, c.period, app.prefs.weekStart).start,
                        amountCents: cents, note: 'Given a job'));
                  } else if (where == 'vault') {
                    app.record([app.event(kind: 'goal_deposit', amountCents: cents, goalId: target)]);
                  } else {
                    app.record([app.event(kind: 'transfer', amountCents: cents, accountId: from, toAccountId: to)]);
                  }
                  Navigator.pop(context);
                  context.toast('Done.');
                },
          child: const Text('Do it'),
        ),
        if (accts.isEmpty) const Text('Add an account in Settings first.'),
      ]),
    );
  }
}

/// Add money to a budget. Asks where it comes from, because those are different things:
/// - from spare money: the money is already counted, it just gets this job (spare goes down);
/// - new cash: money you have that the app doesn't know about yet (total goes up, spare stays the same).
Future<void> addToBudget(BuildContext context, Category c) async {
  final app = context.appRead;
  final ctl = TextEditingController();
  final accts = app.data.accounts.where((a) => !a.archived).toList();
  String? account = accts.firstOrNull?.id;
  final choice = await showDialog<String>(
    context: context,
    builder: (x) => StatefulBuilder(
      builder: (x, set) => AlertDialog(
        title: Text('Add money to ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('For this ${c.period == 'monthly' ? 'month' : 'week'} only. Spare money right now: ${m(app.data.availableToSpend)}.'),
          const SizedBox(height: 10),
          TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ ')),
          if (accts.length > 1) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: account,
              decoration: const InputDecoration(labelText: 'If it is new cash, where is it?'),
              items: [for (final a in accts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => set(() => account = v),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(x, 'spare'), child: const Text('From my spare money')),
          FilledButton(onPressed: () => Navigator.pop(x, 'new'), child: const Text('New cash I have')),
        ],
      ),
    ),
  );
  final cents = (parseCents(ctl.text) ?? 0).abs();
  if (choice == null || cents == 0) return;
  final boost = BudgetAllocation(
      id: newId(), categoryId: c.id, periodStart: periodOf(app.data.todayDate, c.period, app.prefs.weekStart).start,
      amountCents: cents, note: choice == 'new' ? 'New cash' : 'From spare money');
  if (choice == 'new' && account != null) {
    app.record([app.event(kind: 'adjustment', amountCents: cents, accountId: account, note: 'Cash for ${c.name}')], also: [boost]);
  } else {
    app.save(boost);
  }
  if (context.mounted) {
    context.toast(choice == 'new' ? 'Added ${m(cents)} cash to ${c.name}. Spare money unchanged.' : 'Moved ${m(cents)} of spare money into ${c.name}.');
  }
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
