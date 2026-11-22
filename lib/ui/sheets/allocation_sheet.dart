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

class AllocationSheet extends StatefulWidget {
  final String title;
  final int amount;
  final String groupId;
  final DateTime date;
  final Proposal suggested;
  final bool allowModes;
  const AllocationSheet({super.key, required this.title, required this.amount, required this.groupId, required this.date,
      required this.suggested, this.allowModes = true});
  @override
  State<AllocationSheet> createState() => _AllocationSheetState();
}

enum Mode { suggested, manual, single }

class _AllocationSheetState extends State<AllocationSheet> {
  Mode mode = Mode.suggested;
  late List<AllocationLine> lines = [for (final l in widget.suggested.lines) l.copy()];
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
        if (m == Mode.manual) lines = [];
      });

  Future<void> addLine() async {
    final data = context.appRead.data;
    final pick = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Add destination'), children: [
        for (final g in data.goals.where((g) => !g.archived))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'goal:${g.id}'), child: Text('Vault: ${g.name}')),
        for (final cat in data.categories.where((c) => !c.archived))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'cat:${cat.id}'), child: Text('Budget: ${cat.name}')),
      ]),
    );
    if (pick == null) return;
    final id = pick.substring(pick.indexOf(':') + 1);
    setState(() => lines.add(pick.startsWith('goal:')
        ? AllocationLine(TargetKind.goal, id, data.goal(id)!.name, 0)
        : AllocationLine(TargetKind.category, id, data.category(id)!.name, 0)));
  }

  Future<void> commit() async {
    final app = context.appRead;
    if (leftover < 0) return context.toast('You allocated more than ${m(widget.amount)}.');
    final eff = effective;
    final goalLines = eff.where((l) => l.kind == TargetKind.goal && l.cents > 0).toList();
    final catLines = eff.where((l) => l.kind == TargetKind.category && l.cents > 0).toList();
    if (goalLines.isEmpty && catLines.isEmpty) {
      Navigator.pop(context);
      return context.toast('Kept as unallocated money.');
    }
    final summary = [for (final l in [...goalLines, ...catLines]) '${l.label}: ${m(l.cents)}'].join('\n');
    if (!await confirm(context, 'Confirm split', '$summary\n\nUnallocated: ${m(leftover)}')) return;
    final events = [
      for (final l in goalLines)
        app.event(kind: 'goal_deposit', amountCents: l.cents, goalId: l.targetId, groupId: widget.groupId, on: widget.date, note: 'From split'),
    ];
    final allocs = [
      for (final l in catLines)
        () {
          final c = app.data.category(l.targetId)!;
          return BudgetAllocation(
              id: newId(), categoryId: c.id, periodStart: periodOf(widget.date, c.period, app.prefs.weekStart).start,
              amountCents: l.cents, groupId: widget.groupId);
        }()
    ];
    app.record(events, also: allocs, trigger: events.isEmpty ? null : GoalMoved(events.first));
    if (!mounted) return;
    Navigator.pop(context);
    context.toast('Split saved. Undo it anytime from Activity.');
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
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(switch (l.kind) {
                  TargetKind.goal => Icons.savings_rounded,
                  TargetKind.category => Icons.pie_chart_rounded,
                  TargetKind.bills => Icons.event_note_rounded,
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
        if (eff.any((l) => l.kind == TargetKind.bills))
          Text('"Keep for bills" stays in your accounts and is reserved for upcoming bills automatically.', style: context.tt.bodySmall),
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
        Text('Safe to spend after this: ${m(data.availableToSpend - eff.where((l) => l.kind == TargetKind.goal).fold(0, (s, l) => s + l.cents))}',
            style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        FilledButton(onPressed: leftover < 0 ? null : commit, child: const Text('Confirm split')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip - keep it unallocated')),
      ]),
    );
  }
}
