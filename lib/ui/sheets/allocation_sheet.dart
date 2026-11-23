// Confirm-first allocation editor: Suggested / Manual / Single destination, with a live preview.
// Nothing is written until the user taps Confirm.
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
    for (final e in deposits)
      if (e.billId != null && d.goal(e.goalId)?.name == billSavingsName)
        AllocationLine(TargetKind.billSavings, e.billId, 'Bill envelope: ${d.bill(e.billId)?.name ?? 'bill'}', e.amountCents)
      else
        AllocationLine(TargetKind.goal, e.goalId, d.goal(e.goalId)?.name ?? 'Deleted vault (will be removed)', e.amountCents),
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
  /// Same suggestion, but letting unassigned Bill envelope money count toward bills (offered as a switch).
  final Proposal? suggestedWithEnvelope;
  final bool allowModes;
  /// Where the money currently is (editing an existing split). Null for a new split.
  final List<AllocationLine>? current;
  const AllocationSheet({super.key, required this.title, required this.amount, required this.groupId, required this.date,
      required this.suggested, this.suggestedWithEnvelope, this.allowModes = true, this.current});
  @override
  State<AllocationSheet> createState() => _AllocationSheetState();
}

enum Mode { suggested, manual, single }

class _AllocationSheetState extends State<AllocationSheet> {
  late Mode mode = widget.current != null ? Mode.manual : Mode.suggested;
  bool useEnvelope = false;
  Proposal get base => useEnvelope && widget.suggestedWithEnvelope != null ? widget.suggestedWithEnvelope! : widget.suggested;
  late List<AllocationLine> lines = [for (final l in widget.current ?? widget.suggested.lines) l.copy()];
  bool get editing => widget.current != null;
  final controllers = <AllocationLine, TextEditingController>{};
  String? singleTarget; // 'goal:<id>' | 'cat:<id>' | 'none'

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

  int get allocated => effective.where((l) => l.kind != TargetKind.unallocated).fold(0, (s, l) => s + l.cents);
  int get leftover => widget.amount - allocated;
  Map<String, int> get assign => useEnvelope && mode != Mode.single ? base.assign : const {};

  /// Recalculate: back to the suggestion (drops manual edits).
  void setMode(Mode m) => setState(() {
        mode = m;
        controllers.clear();
        if (m == Mode.suggested) lines = [for (final l in base.lines) l.copy()];
        if (m == Mode.manual) lines = [for (final l in widget.current ?? base.lines) l.copy()];
      });

  Future<void> addLine() async {
    final data = context.appRead.data;
    final pick = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Add destination'), children: [
        for (final b in data.bills.where((b) => !b.archived && !b.incoming))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'env:${b.id}'), child: Text('Bill envelope: ${b.name}')),
        for (final g in data.goals.where((g) => !g.archived && g.name != billSavingsName))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'goal:${g.id}'), child: Text('Vault: ${g.name}')),
        for (final cat in data.categories.where((c) => !c.archived))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'cat:${cat.id}'), child: Text('Budget: ${cat.name}')),
      ]),
    );
    if (pick == null) return;
    final id = pick.substring(pick.indexOf(':') + 1);
    setState(() => lines.add(switch (pick.substring(0, pick.indexOf(':'))) {
          'env' => AllocationLine(TargetKind.billSavings, id, 'Bill envelope: ${data.bill(id)!.name}', 0),
          'goal' => AllocationLine(TargetKind.goal, id, data.goal(id)!.name, 0),
          _ => AllocationLine(TargetKind.category, id, data.category(id)!.name, 0),
        }));
  }

  /// Budget lines: how this period's budget changes compared with what was suggested
  /// (editing Food 120 -> 100 lowers Food by 20 this period; removing a budget line sets it to $0 from this paycheck).
  Map<String, int> budgetChanges(List<AllocationLine> eff) {
    if (editing) return const {};
    final suggested = {for (final l in base.lines) if (l.kind == TargetKind.covered) l.targetId!: l.cents};
    final chosen = {for (final l in eff) if (l.kind == TargetKind.covered && l.targetId != null) l.targetId!: l.cents};
    return {
      for (final id in {...suggested.keys, ...chosen.keys})
        if ((chosen[id] ?? 0) - (suggested[id] ?? 0) != 0) id: (chosen[id] ?? 0) - (suggested[id] ?? 0),
    };
  }

  int sumOf(List<AllocationLine> eff, TargetKind k) => eff.where((l) => l.kind == k).fold(0, (s, l) => s + l.cents);

  /// Bills this split leaves short: (need, cents missing). Bills before payday are short on the due date;
  /// later bills just need more from the next paychecks.
  List<(BillNeed, int)> shortfalls(List<AllocationLine> eff) {
    final given = <String, int>{};
    for (final l in eff) {
      final k = billKey(l);
      if (k != null) given[k] = (given[k] ?? 0) + l.cents;
    }
    return [
      for (final n in base.bills)
        if (n.recommended > (given[needKey(n)] ?? 0)) (n, n.recommended - (given[needKey(n)] ?? 0)),
    ];
  }

  /// A bill can have a payment before payday (kept in accounts) and a later one (Bill envelope): keyed apart.
  String? billKey(AllocationLine l) => l.targetId == null
      ? null
      : switch (l.kind) { TargetKind.bills => 'now:${l.targetId}', TargetKind.billSavings => 'later:${l.targetId}', _ => null };
  String needKey(BillNeed n) => '${n.beforePayday ? 'now' : 'later'}:${n.bill.id}';

  int freeAfter(List<AllocationLine> eff) {
    final d = context.appRead.data;
    final nearIds = {for (final n in base.bills) if (n.beforePayday) n.bill.id};
    final assignedNear = assign.entries.where((e) => nearIds.contains(e.key)).fold(0, (s, e) => s + e.value);
    return d.availableToSpend + assignedNear - sumOf(eff, TargetKind.goal) - sumOf(eff, TargetKind.billSavings) -
        sumOf(eff, TargetKind.category) - budgetChanges(eff).values.fold(0, (s, v) => s + v);
  }

  Future<void> commit() async {
    final app = context.appRead;
    final d = app.data;
    if (leftover < 0) return context.toast('You allocated more than ${m(widget.amount)}.');
    final eff = effective;
    // lines pointing at a deleted vault/category/bill are dropped (their money returns to unallocated)
    final goalLines = eff.where((l) => l.kind == TargetKind.goal && l.cents > 0 && d.goal(l.targetId) != null).toList();
    final catLines = eff.where((l) => l.kind == TargetKind.category && l.cents > 0 && d.category(l.targetId) != null).toList();
    final envLines = eff.where((l) => l.kind == TargetKind.billSavings && l.cents > 0 && (l.targetId == null || d.bill(l.targetId) != null)).toList();
    final changes = {for (final e in budgetChanges(eff).entries) if (d.category(e.key) != null) e.key: e.value};
    final moves = {for (final e in assign.entries) if (d.bill(e.key) != null) e.key: e.value};
    if (goalLines.isEmpty && catLines.isEmpty && changes.isEmpty && envLines.isEmpty && moves.isEmpty && !editing) {
      Navigator.pop(context);
      return context.toast('Kept as free money.');
    }
    final short = shortfalls(eff);
    final free = freeAfter(eff);
    String billName(String? id) => id == null ? 'bills' : d.bill(id)?.name ?? 'bill';
    final summary = [
      for (final l in envLines) 'Bill envelope for ${billName(l.targetId)}: +${m(l.cents)}',
      for (final e in moves.entries) 'Assign ${m(e.value)} of unassigned Bill savings to ${billName(e.key)}',
      for (final l in goalLines) '${l.label}: +${m(l.cents)}',
      for (final l in catLines) '${l.label} budget: +${m(l.cents)}',
      for (final e in changes.entries) () {
        final s = d.categoryStatus(d.category(e.key)!);
        return '${s.category.name} left this ${s.category.period == 'monthly' ? 'month' : 'week'}: ${m(s.remaining)} -> ${m(s.remaining + e.value)}';
      }(),
      for (final (n, c) in short.where((s) => s.$1.beforePayday)) '\nWarning: ${n.name} is ${m(c)} short for ${prettyDate(n.due)}.',
      if (free < 0) '\nWarning: free money goes negative (${m(free)}).',
    ].join('\n');
    if (!await confirm(context, 'Confirm split', '$summary\n\nFree money left: ${m(free)}')) return;

    final also = <Entity>[];
    final events = [
      for (final l in goalLines)
        app.event(kind: 'goal_deposit', amountCents: l.cents, goalId: l.targetId, groupId: widget.groupId, on: widget.date, note: 'From split'),
    ];
    if (envLines.isNotEmpty || moves.isNotEmpty) {
      var vault = d.billEnvelope;
      if (vault == null) {
        final need = base.bills.fold(0, (s, n) => s + n.amount);
        final put = envLines.fold(0, (s, l) => s + l.cents);
        vault = SavingsGoal(id: newId(), name: billSavingsName, goalCents: need > put ? need : (put > 0 ? put : 1), contributionFreq: 'none', color: 0xFFFFA94D);
        also.add(vault);
      }
      for (final l in envLines) {
        events.add(app.event(kind: 'goal_deposit', amountCents: l.cents, goalId: vault.id, billId: l.targetId, groupId: widget.groupId,
            on: widget.date, note: l.targetId == null ? 'Saving for later bills' : 'For ${billName(l.targetId)}'));
      }
      // Assigning unassigned envelope money: out of "no bill", into that bill. The envelope total doesn't change.
      for (final e in moves.entries) {
        events.add(app.event(kind: 'goal_withdraw', amountCents: e.value, goalId: vault.id, reason: 'planned', groupId: widget.groupId,
            on: widget.date, note: 'Assigned to ${billName(e.key)}'));
        events.add(app.event(kind: 'goal_deposit', amountCents: e.value, goalId: vault.id, billId: e.key, groupId: widget.groupId,
            on: widget.date, note: 'Assigned to ${billName(e.key)}'));
      }
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
      final first = events.where((e) => e.kind == 'goal_deposit' && e.note != null && !e.note!.startsWith('Assigned')).firstOrNull;
      app.record(events, also: [...also, ...allocs], trigger: first == null ? null : GoalMoved(first));
    }
    if (!mounted) return;
    Navigator.pop(context);
    context.toast(editing ? 'Split updated.' : 'Split saved. Change it anytime from Activity.');
  }

  Widget amountBox(AllocationLine l) => SizedBox(
        width: 104,
        child: TextField(
          controller: ctl(l),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '\$ ', isDense: true),
          onChanged: (v) => setState(() => l.cents = (parseCents(v) ?? 0).clamp(0, 1 << 40)),
        ),
      );

  Widget lineRow(AllocationLine l) {
    final n = l.need;
    final icon = Icon(switch (l.kind) {
      TargetKind.goal => Icons.savings_rounded,
      TargetKind.category => Icons.pie_chart_rounded,
      TargetKind.bills => Icons.event_note_rounded,
      TargetKind.covered => Icons.shopping_basket_rounded,
      TargetKind.billSavings => Icons.receipt_long_rounded,
      TargetKind.unallocated => Icons.account_balance_wallet_rounded,
    }, color: switch (l.kind) { TargetKind.goal => Accents.savings, TargetKind.bills || TargetKind.billSavings => Accents.warn, _ => null });
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: n == null ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(top: n == null ? 0 : 4), child: icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: n == null ? null : FontWeight.w700)),
            if (n != null) Text(billDetail(n), style: context.tt.bodySmall),
            if (n != null && l.cents < n.recommended)
              Text(n.beforePayday ? '${m(n.recommended - l.cents)} short for the due date' : '${m(n.recommended - l.cents)} less than suggested: later paychecks need more',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: n.beforePayday ? Accents.danger : Accents.warn)),
          ]),
        ),
        amountBox(l),
        IconButton(tooltip: 'Skip', onPressed: () => setState(() => lines.remove(l)), icon: const Icon(Icons.close_rounded, size: 18)),
      ]),
    );
  }

  String billDetail(BillNeed n) {
    final parts = [
      '${m(n.amount - n.paid)} left to pay',
      if (n.inEnvelope > 0) '${m(n.inEnvelope)} in envelope',
      if (n.fromMoneyYouHave > 0) '${m(n.fromMoneyYouHave)} from money you have',
      '${m(n.stillNeeded)} still needed',
      n.beforePayday ? 'due before payday' : '${n.paychecksLeft} paycheck${n.paychecksLeft == 1 ? '' : 's'} left',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final data = context.app.data;
    final eff = effective;
    final billLines = lines.where((l) => l.kind == TargetKind.bills || l.kind == TargetKind.billSavings).toList();
    final otherLines = lines.where((l) => !billLines.contains(l) && l.kind != TargetKind.unallocated).toList();
    final lined = {for (final l in billLines) billKey(l)};
    final coveredBills = base.bills.where((n) => n.recommended == 0 && !lined.contains(needKey(n))).toList();
    final short = shortfalls(eff);
    final unassigned = data.billEnvelopeUnassigned;
    final free = freeAfter(eff);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Nothing is moved until you confirm. Uses only the bills you already have.', style: context.tt.bodySmall),
        const SizedBox(height: 12),
        if (widget.allowModes)
          SegmentedButton<Mode>(
            showSelectedIcon: false,
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
          if (billLines.isNotEmpty || coveredBills.isNotEmpty) ...[
            const Section('Bills'),
            Text('Bills before payday stay in your accounts. Later bills go into the Bill envelope, set aside for that bill.',
                style: context.tt.bodySmall),
            const SizedBox(height: 8),
            for (final l in billLines) lineRow(l),
            for (final n in coveredBills)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Accents.savings, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${n.name}: covered (${m(n.setAside)} set aside, due ${prettyDate(n.due)})', style: context.tt.bodySmall)),
                ]),
              ),
            if (widget.suggestedWithEnvelope != null && unassigned > 0 && !editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: useEnvelope,
                onChanged: (v) {
                  useEnvelope = v;
                  setMode(Mode.suggested);
                },
                title: Text('Use ${m(unassigned)} unassigned Bill savings'),
                subtitle: const Text('Money already in the envelope that is not set aside for any bill. Off unless you turn it on.'),
              ),
          ],
          if (otherLines.isNotEmpty) const Section('Budgets & savings'),
          for (final l in otherLines) lineRow(l),
          TextButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Add destination')),
        ],
        const Divider(height: 24),
        Row(children: [
          const Expanded(child: Text('Spare money from this paycheck', style: TextStyle(fontWeight: FontWeight.w700))),
          Money(leftover, color: leftover < 0 ? Accents.danger : null),
        ]),
        if (eff.any((l) => l.kind == TargetKind.covered) || budgetChanges(eff).isNotEmpty)
          Text("Budget lines are this paycheck's money for that budget. Change the amount and the budget changes for this period; skip the line and it gets \$0 from this paycheck.",
              style: context.tt.bodySmall),
        for (final (n, c) in short.where((s) => s.$1.beforePayday))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${n.name} is ${m(c)} short for ${prettyDate(n.due)}. Free money will go negative unless more comes in.',
                style: const TextStyle(color: Accents.danger, fontWeight: FontWeight.w700)),
          ),
        if (mode == Mode.suggested && widget.amount < base.bills.fold(0, (s, n) => s + n.recommended))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('This paycheck is not enough for every bill. The soonest bills were funded first.',
                style: TextStyle(color: Accents.warn, fontWeight: FontWeight.w700)),
          ),
        if (base.bills.any((n) => !n.beforePayday))
          Text('Later-bill amounts assume your next paychecks arrive. If one is missed, the next suggestion goes up.', style: context.tt.bodySmall),
        const Section('Preview'),
        for (final l in eff.where((l) => l.cents > 0 && (l.kind == TargetKind.goal || l.kind == TargetKind.category)))
          if (l.kind == TargetKind.goal ? data.goal(l.targetId) != null : data.category(l.targetId) != null)
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
        Text('Free money after this: ${m(free)}',
            style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: free < 0 ? Accents.danger : null)),
        const SizedBox(height: 16),
        FilledButton(onPressed: leftover < 0 ? null : commit, child: Text(mode == Mode.suggested && !editing ? 'Accept split' : 'Confirm split')),
        if (!editing && mode != Mode.single)
          OutlinedButton.icon(onPressed: () => setMode(Mode.suggested), icon: const Icon(Icons.refresh_rounded), label: const Text('Recalculate')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(editing ? 'Cancel - change nothing' : 'Cancel - keep it all as spare money')),
      ]),
    );
  }
}
