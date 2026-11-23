// Confirm-first allocation editor: Suggested / Manual / Single destination, with a live preview.
import 'package:material_ui/material_ui.dart';

import '../../clover/brain.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/allocation.dart';
import '../common.dart';
import '../theme.dart';

/// Opens the split editor for money that was already split (Extra Money / paycheck).
Future<void> openEditSplit(BuildContext context, String groupId) async {
  final d = context.appRead.data;
  final source = d.ledger.active.where((e) => e.groupId == groupId && (e.kind == 'income' || e.kind == 'refund')).toList();
  final deposits = d.ledger.active.where((e) => e.groupId == groupId && e.kind == 'goal_deposit').toList();
  final allocs = d.budgetAllocations.where((a) => a.groupId == groupId && a.amountCents > 0).toList();
  final placed = deposits.fold<int>(0, (s, e) => s + e.amountCents) + allocs.fold<int>(0, (s, a) => s + a.amountCents);
  final amount = source.isEmpty ? placed : source.fold<int>(0, (s, e) => s + e.amountCents);
  final current = <AllocationLine>[
    for (final e in deposits) AllocationLine(TargetKind.goal, e.goalId, d.goal(e.goalId)?.name ?? 'Deleted vault (will be removed)', e.amountCents),
    for (final a in allocs)
      AllocationLine(TargetKind.category, a.categoryId, d.category(a.categoryId)?.name ?? 'Deleted category (will be removed)', a.amountCents),
  ];
  final date = source.firstOrNull?.occurredOn ?? deposits.firstOrNull?.occurredOn ?? today();
  await sheet(context, AllocationSheet(
      title: 'Edit split of ${m(amount)}', amount: amount, groupId: groupId, date: date,
      suggested: suggestExtra(d, amount), current: current));
}

class AllocationSheet extends StatefulWidget {
  final String title;
  final int amount;
  final String groupId;
  final DateTime date;
  final Proposal suggested;
  final bool allowModes;
  /// Where the money currently is (editing an existing split). Null for a new split.
  final List<AllocationLine>? current;
  const AllocationSheet({super.key, required this.title, required this.amount, required this.groupId, required this.date,
      required this.suggested, this.allowModes = true, this.current});
  @override
  State<AllocationSheet> createState() => _AllocationSheetState();
}

enum Mode { suggested, manual, single }

class _AllocationSheetState extends State<AllocationSheet> {
  late Mode mode = widget.current != null ? Mode.manual : Mode.suggested;
  late List<AllocationLine> lines = [for (final l in widget.current ?? widget.suggested.lines) l.copy()];
  bool get editing => widget.current != null;
  final controllers = <AllocationLine, TextEditingController>{};
  String? singleTarget; // 'goal:<id>' | 'cat:<id>' | 'none'
  bool done = false;

  TextEditingController ctl(AllocationLine l) => controllers.putIfAbsent(l, () => TextEditingController(text: centsToInput(l.cents)));

  List<AllocationLine> get effective {
    if (mode != Mode.single) return lines;
    final t = singleTarget;
    if (t == null || t == 'none') return [AllocationLine(TargetKind.unallocated, null, 'Unallocated', widget.amount)];
    final data = context.appRead.data;
    final id = t.substring(t.indexOf(':') + 1);
    return t.startsWith('goal:')
        ? [AllocationLine(TargetKind.goal, id, data.goal(id)?.name ?? 'Goal', widget.amount)]
        : [AllocationLine(TargetKind.category, id, data.category(id)?.name ?? 'Category', widget.amount)];
  }

  int get allocated => effective.fold(0, (s, l) => s + l.cents);
  int get leftover => widget.amount - allocated;

  void setMode(Mode m) => setState(() {
        mode = m;
        controllers.clear();
        if (m == Mode.suggested) lines = [for (final l in widget.suggested.lines) l.copy()];
        if (m == Mode.manual) lines = [for (final l in widget.current ?? const <AllocationLine>[]) l.copy()];
      });

  Future<void> addLine() async {
    final data = context.appRead.data;
    final pick = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Add destination'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'bills:'), child: const Text('Save for upcoming bills')),
        for (final g in data.goals.where((g) => !g.archived))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'goal:${g.id}'), child: Text('Vault: ${g.name}')),
        for (final cat in data.categories.where((c) => !c.archived))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'cat:${cat.id}'), child: Text('Budget: ${cat.name}')),
      ]),
    );
    if (pick == null) return;
    final id = pick.substring(pick.indexOf(':') + 1);
    if (pick == 'bills:') {
      return setState(() => lines.add(AllocationLine(TargetKind.bills, null, 'Keep for upcoming bills', 0)));
    }
    setState(() => lines.add(pick.startsWith('goal:')
        ? AllocationLine(TargetKind.goal, id, data.goal(id)!.name, 0)
        : AllocationLine(TargetKind.category, id, data.category(id)!.name, 0)));
  }

  /// Budget lines: how this period's budget changes compared with what was suggested
  /// (editing Food 120 -> 100 lowers Food by 20 this period; removing a budget line sets it to $0 from this paycheck).
  Map<String, int> budgetChanges(List<AllocationLine> eff) {
    if (editing) return const {};
    final suggested = {for (final l in widget.suggested.lines) if (l.kind == TargetKind.covered) l.targetId!: l.cents};
    final chosen = {for (final l in eff) if (l.kind == TargetKind.covered && l.targetId != null) l.targetId!: l.cents};
    return {
      for (final id in {...suggested.keys, ...chosen.keys})
        if ((chosen[id] ?? 0) - (suggested[id] ?? 0) != 0) id: (chosen[id] ?? 0) - (suggested[id] ?? 0),
    };
  }

  int sumOf(List<AllocationLine> eff, TargetKind k) => eff.where((l) => l.kind == k).fold(0, (s, l) => s + l.cents);

  Future<void> commit() async {
    final app = context.appRead;
    final d = app.data;
    if (leftover < 0) return context.toast('You allocated more than ${m(widget.amount)}.');
    final eff = effective;
    // lines pointing at a deleted vault/category are dropped (their money returns to unallocated)
    final goalLines = eff.where((l) => l.kind == TargetKind.goal && l.cents > 0 && d.goal(l.targetId) != null).toList();
    final catLines = eff.where((l) => l.kind == TargetKind.category && l.cents > 0 && d.category(l.targetId) != null).toList();
    final changes = {for (final e in budgetChanges(eff).entries) if (d.category(e.key) != null) e.key: e.value};
    final billSave = sumOf(eff, TargetKind.billSavings);
    if (goalLines.isEmpty && catLines.isEmpty && changes.isEmpty && billSave == 0 && !editing) {
      Navigator.pop(context);
      return context.toast('Kept as free money.');
    }
    final shortBills = sumOf(widget.suggested.lines, TargetKind.bills) - sumOf(eff, TargetKind.bills);
    final summary = [
      for (final l in goalLines) '${l.label}: +${m(l.cents)}',
      if (billSave > 0) 'Bill savings: +${m(billSave)}',
      for (final l in catLines) '${l.label} budget: +${m(l.cents)}',
      for (final e in changes.entries) () {
        final s = d.categoryStatus(d.category(e.key)!);
        return '${s.category.name} left this ${s.category.period == 'monthly' ? 'month' : 'week'}: ${m(s.remaining)} -> ${m(s.remaining + e.value)}';
      }(),
      if (shortBills > 0) '\nWarning: bills due before payday are ${m(shortBills)} short with this split.',
    ].join('\n');
    if (!await confirm(context, 'Confirm split', '$summary\n\nFree money left: ${m(leftover)}')) return;

    final also = <Entity>[];
    final events = [
      for (final l in goalLines)
        app.event(kind: 'goal_deposit', amountCents: l.cents, goalId: l.targetId, groupId: widget.groupId, on: widget.date, note: 'From split'),
    ];
    if (billSave > 0) {
      var vault = d.goals.where((g) => g.name == billSavingsName && !g.archived).firstOrNull;
      if (vault == null) {
        final need = laterBills(d).fold(0, (s, l) => s + l.amount);
        vault = SavingsGoal(id: newId(), name: billSavingsName, goalCents: need > billSave ? need : billSave, contributionFreq: 'none', color: 0xFFFFA94D);
        also.add(vault);
      }
      events.add(app.event(kind: 'goal_deposit', amountCents: billSave, goalId: vault.id, groupId: widget.groupId, on: widget.date, note: 'Saving for later bills'));
    }
    BudgetAllocation alloc(String categoryId, int cents) {
      final c = d.category(categoryId)!;
      return BudgetAllocation(
          id: newId(), categoryId: c.id, periodStart: periodOf(widget.date, c.period, app.prefs.weekStart).start,
          amountCents: cents, groupId: widget.groupId, note: 'From split');
    }
    final allocs = [for (final l in catLines) alloc(l.targetId!, l.cents), for (final e in changes.entries) alloc(e.key, e.value)];
    if (editing) {
      app.replaceSplit(widget.groupId, events, allocs);
    } else {
      app.record(events, also: [...also, ...allocs], trigger: events.isEmpty ? null : GoalMoved(events.first));
    }
    if (!mounted) return;
    Navigator.pop(context);
    context.toast(editing ? 'Split updated.' : 'Split saved. Change it anytime from Activity.');
  }

  @override
  Widget build(BuildContext context) {
    final data = context.app.data;
    final eff = effective;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Nothing is moved until you confirm.', style: context.tt.bodySmall),
        const SizedBox(height: 12),
        if (widget.allowModes)
          SegmentedButton<Mode>(
            segments: const [
              ButtonSegment(value: Mode.suggested, label: Text('Suggested')),
              ButtonSegment(value: Mode.manual, label: Text('Manual')),
              ButtonSegment(value: Mode.single, label: Text('Single')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setMode(s.first),
          ),
        const SizedBox(height: 12),
        if (mode == Mode.single)
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: singleTarget,
            decoration: const InputDecoration(labelText: 'Put it all in'),
            items: [
              const DropdownMenuItem(value: 'none', child: Text('Unallocated balance')),
              for (final g in data.goals.where((g) => !g.archived)) DropdownMenuItem(value: 'goal:${g.id}', child: Text('Vault: ${g.name}')),
              for (final c in data.categories.where((c) => !c.archived)) DropdownMenuItem(value: 'cat:${c.id}', child: Text('Budget: ${c.name}')),
            ],
            onChanged: (v) => setState(() => singleTarget = v),
          )
        else ...[
          Text('Tap any amount to change it, or X to remove a line.', style: context.tt.bodySmall),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(switch (l.kind) {
                  TargetKind.goal => Icons.savings_rounded,
                  TargetKind.category => Icons.pie_chart_rounded,
                  TargetKind.bills => Icons.event_note_rounded,
                  TargetKind.covered => Icons.shopping_basket_rounded,
                  TargetKind.billSavings => Icons.receipt_long_rounded,
                  TargetKind.unallocated => Icons.account_balance_wallet_rounded,
                }, color: switch (l.kind) { TargetKind.goal => Accents.savings, TargetKind.bills => Accents.warn, _ => null }),
                const SizedBox(width: 10),
                Expanded(child: Text(l.label, overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: ctl(l),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixText: '\$ ', isDense: true),
                    onChanged: (v) => setState(() => l.cents = (parseCents(v) ?? 0).clamp(0, 1 << 40)),
                  ),
                ),
                IconButton(onPressed: () => setState(() => lines.remove(l)), icon: const Icon(Icons.close_rounded, size: 18)),
              ]),
            ),
          TextButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Add destination')),
        ],
        const Divider(height: 24),
        Row(children: [
          const Expanded(child: Text('Unallocated / spending money')),
          Money(leftover, color: leftover < 0 ? Accents.danger : null),
        ]),
        if (eff.any((l) => l.kind == TargetKind.covered) || budgetChanges(eff).isNotEmpty)
          Text("Budget lines are this paycheck's money for that budget. Change the amount and the budget changes for this period; remove the line and it gets \$0 from this paycheck.", style: context.tt.bodySmall),
        if (sumOf(eff, TargetKind.billSavings) > 0) ...[
          Text('Save for later bills goes into your Bill savings vault, ready for:', style: context.tt.bodySmall),
          for (final l in laterBills(data))
            Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text('• ${l.name}: ${m(l.amount)} due ${prettyDate(l.due)} (${m(l.perPaycheck)} per paycheck)', style: context.tt.bodySmall)),
        ],
        if (sumOf(widget.suggested.lines, TargetKind.bills) > sumOf(eff, TargetKind.bills))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Bills due before payday are ${m(sumOf(widget.suggested.lines, TargetKind.bills) - sumOf(eff, TargetKind.bills))} short with this split. Free money will go negative.',
                style: const TextStyle(color: Accents.danger, fontWeight: FontWeight.w700)),
          ),
        if (eff.any((l) => l.kind == TargetKind.bills)) ...[
          Text('"Keep for bills" stays in your accounts and covers these bills before payday:', style: context.tt.bodySmall),
          for (final o in data.upcomingBills(days: data.daysUntilHorizon).where((o) => !o.bill.incoming))
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('• ${o.bill.name}: ${m(o.remainingCents)} (${prettyDate(o.due)})', style: context.tt.bodySmall),
            ),
        ],
        const Section('Preview'),
        for (final l in eff.where((l) => l.cents > 0 && (l.kind == TargetKind.goal || l.kind == TargetKind.category)))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: Text(l.label)),
              if (l.kind == TargetKind.goal) ...[
                Text('${m(data.ledger.goalBalance(l.targetId!))} → '),
                Money(data.ledger.goalBalance(l.targetId!) + l.cents, color: Accents.savings),
              ] else ...[
                Text('${m(data.categoryStatus(data.category(l.targetId)!).remaining)} left → '),
                Money(data.categoryStatus(data.category(l.targetId)!).remaining + l.cents),
              ],
            ]),
          ),
        Text(
            'Free money after this: ${m(data.availableToSpend - sumOf(eff, TargetKind.goal) - sumOf(eff, TargetKind.billSavings) - sumOf(eff, TargetKind.category) - budgetChanges(eff).values.fold(0, (s, v) => s + v))}',
            style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        FilledButton(onPressed: leftover < 0 ? null : commit, child: const Text('Confirm split')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip - keep it unallocated')),
      ]),
    );
  }
}
