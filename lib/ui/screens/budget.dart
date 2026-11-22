import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/finance.dart';
import '../../domain/forecast.dart';
import '../app.dart';
import '../common.dart';
import '../sheets/allocation_sheet.dart';
import '../sheets/entry_sheet.dart';
import '../theme.dart';
import 'activity.dart';
import 'forecast.dart';
import 'plan.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  bool archived = false;

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final fc = buildForecast(d, weeks: 8);
    final cats = d.categories.where((c) => c.archived == archived).map(d.categoryStatus).toList();
    return Scaffold(
      appBar: const PageBar('Budget'),
      body: PageBody(children: [
        Panel(
          color: Accents.savings.withValues(alpha: 0.12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyPlanScreen())),
          child: const Row(children: [
            Icon(Icons.auto_graph_rounded, color: Accents.savings),
            SizedBox(width: 10),
            Expanded(child: Text('Weekly plan: how much to put where', style: TextStyle(fontWeight: FontWeight.w800))),
            Icon(Icons.chevron_right_rounded),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForecastScreen())),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Forecast', style: context.tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              BufferChip(fc.bufferStatus),
              const Icon(Icons.chevron_right_rounded),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 24, runSpacing: 8, children: [
              _kv(context, 'Before next payday', fc.balanceAtPayday),
              _kv(context, 'In 4 weeks', fc.at(4).balance),
              _kv(context, 'In 8 weeks', fc.at(8).balance),
              _kv(context, 'Daily allowance', d.dailySafeSpend),
            ]),
            const SizedBox(height: 8),
            Text('Projection · assumes expected paychecks, scheduled bills, and your recent spending pace. Tap for What-If.',
                style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
        ),
        Section('Paydays', trailing: TextButton.icon(onPressed: () => sheet(context, const ScheduleEditor()), icon: const Icon(Icons.add), label: const Text('Add'))),
        if (d.schedules.isEmpty)
          const Panel(child: Text('No income schedule yet. Add one so STACKD knows when money arrives.'))
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final s in d.schedules)
                ListTile(
                  leading: const Icon(Icons.payments_rounded, color: Accents.income),
                  title: Text(s.name),
                  subtitle: Text('${freqLabel(s.frequency)} · expected ${m(s.expectedCents)}'
                      '${s.frequency != 'irregular' ? ' · next ${_next(s, d)}' : ''}${s.active ? '' : ' · paused'}'),
                  trailing: IconButton(
                      tooltip: 'Log payday', icon: const Icon(Icons.add_card_rounded), onPressed: () => openQuickAdd(context, kind: 'income')),
                  onTap: () => sheet(context, ScheduleEditor(existing: s)),
                ),
            ]),
          ),
        Section('Categories', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: () => setState(() => archived = !archived), child: Text(archived ? 'Active' : 'Archived')),
          IconButton(tooltip: 'New category', onPressed: () => sheet(context, const CategoryEditor()), icon: const Icon(Icons.add)),
        ])),
        if (cats.isEmpty) const Empty('No categories here.'),
        for (final s in cats) Padding(padding: const EdgeInsets.only(bottom: 8), child: CategoryCard(s)),
      ]),
    );
  }

  String _next(IncomeSchedule s, FinanceData d) {
    final n = nextOccurrence(s.anchorDate, s.frequency, d.todayDate);
    return n == null ? '-' : prettyDate(n);
  }

  Widget _kv(BuildContext context, String k, int v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
        Money(v, size: 18, color: v < 0 ? Accents.danger : null),
      ]);
}

class BufferChip extends StatelessWidget {
  final String status;
  const BufferChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'healthy' => ('Buffer healthy', Accents.savings),
      'tight' => ('Buffer tight', Accents.warn),
      _ => ('Projected short', Accents.danger),
    };
    return Chip(label: Text(label), side: BorderSide(color: color), labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700), visualDensity: VisualDensity.compact);
  }
}

class CategoryCard extends StatelessWidget {
  final CategoryStatus s;
  const CategoryCard(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = s.category;
    return Panel(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryDetail(c.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CatDot(c),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              s.hasLimit
                  ? '${m(s.spent)} of ${m(s.budget)} ${c.period == 'monthly' ? 'this month' : 'this week'}'
                      '${s.extra != 0 || s.rollover != 0 ? ' (${m(s.limit)} limit${s.extra != 0 ? ' + ${m(s.extra)} from extra money' : ''}${s.rollover != 0 ? ' ${formatCents(s.rollover, showPlus: true)} rollover' : ''})' : ''}'
                  : '${m(s.spent)} ${c.period == 'monthly' ? 'this month' : 'this week'} · no limit',
              style: context.tt.bodySmall,
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (s.hasLimit) Money(s.remaining, color: s.remaining < 0 ? Accents.danger : Accents.savings),
            if (s.hasLimit) Text(s.remaining < 0 ? 'over' : 'left', style: context.tt.labelSmall),
          ]),
          categoryMenu(context, c),
        ]),
        if (s.hasLimit) ...[const SizedBox(height: 10), Bar(s.spent, s.budget, color: Color(c.color))],
        const SizedBox(height: 6),
        Text(
          [
            'Last period ${m(s.previousSpent)}',
            if (s.rollover != 0) 'rollover ${formatCents(s.rollover, showPlus: true)}',
            if (s.extra != 0) 'extra +${m(s.extra)}',
            if (c.essential) 'essential',
          ].join(' · '),
          style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openQuickAdd(context, categoryId: c.id),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text(c.essential ? 'Paid / spent' : 'I spent'),
          ),
        ),
      ]),
    );
  }
}

const _catDeleteBody = 'Past transactions stay in your history and balances, but show as Uncategorized.';

Widget categoryMenu(BuildContext context, Category c) => ItemMenu(
      what: c.name,
      deleteBody: _catDeleteBody,
      onEdit: () => sheet(context, CategoryEditor(existing: c)),
      toDelete: () => [c],
      afterDelete: () {
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      },
    );

class CategoryDetail extends StatelessWidget {
  final String id;
  const CategoryDetail(this.id, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final c = d.category(id);
    if (c == null) return const Scaffold(body: Empty('Category not found'));
    final events = d.ledger.active.where((e) => e.categoryId == id).toList()..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    final boosts = d.budgetAllocations.where((a) => a.categoryId == id).toList()..sort((a, b) => b.periodStart.compareTo(a.periodStart));
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: PageBody(children: [
        CategoryCard(d.categoryStatus(c)),
        if (boosts.isNotEmpty) ...[
          const Section('Extra budget added'),
          Text('Money from an Extra Money / paycheck split added to this category. Remove it or move it elsewhere.', style: context.tt.bodySmall),
          for (final a in boosts)
            Card(
              margin: const EdgeInsets.only(top: 6),
              child: ListTile(
                leading: const Icon(Icons.add_card_rounded),
                title: Text('+${m(a.amountCents)} for the ${c.period == 'monthly' ? 'month' : 'week'} of ${prettyDate(a.periodStart)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (a.groupId != null)
                    IconButton(tooltip: 'Edit split', icon: const Icon(Icons.call_split_rounded), onPressed: () => openEditSplit(context, a.groupId!)),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final app = context.appRead;
                      if (await confirm(context, 'Remove this +${m(a.amountCents)}?', 'Your ${c.name} budget goes back down. No money moves.', ok: 'Remove')) {
                        app.removeBoost(a);
                      }
                    },
                  ),
                ]),
              ),
            ),
        ],
        const Section('History'),
        if (events.isEmpty) const Empty('No transactions in this category yet.'),
        for (final e in events.take(300)) EventTile(e),
      ]),
    );
  }
}

class CategoryEditor extends StatefulWidget {
  final Category? existing;
  const CategoryEditor({super.key, this.existing});
  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final form = GlobalKey<FormState>();
  late final c = widget.existing ?? Category(id: newId(), name: '', color: pickColors[8]);
  late final name = TextEditingController(text: c.name);
  late final limit = TextEditingController(text: c.limitCents == null ? '' : centsToInput(c.limitCents!));

  void save() {
    if (!form.currentState!.validate()) return;
    c
      ..name = name.text.trim()
      ..limitCents = limit.text.trim().isEmpty ? null : parseCents(limit.text);
    if (widget.existing == null) c.sort = context.appRead.data.categories.length;
    context.appRead.save(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existing == null ? 'New category' : 'Edit category', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Name it' : null),
            const SizedBox(height: 12),
            TextFormField(
              controller: limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Spending limit (optional)', prefixText: '\$ '),
              validator: (v) => (v ?? '').trim().isEmpty || (parseCents(v!) ?? -1) >= 0 ? null : 'Invalid amount',
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'weekly', label: Text('Weekly')), ButtonSegment(value: 'monthly', label: Text('Monthly'))],
              selected: {c.period},
              onSelectionChanged: (s) => setState(() => c.period = s.first),
            ),
            SwitchListTile(value: c.rollover, onChanged: (v) => setState(() => c.rollover = v), title: const Text('Roll over unused budget'),
                subtitle: const Text('Leftover (or overspend) carries into the next period')),
            SwitchListTile(value: c.essential, onChanged: (v) => setState(() => c.essential = v), title: const Text('Essential'),
                subtitle: const Text('Clover never scolds necessary spending')),
            const Section('Color'),
            ColorChooser(value: c.color, onChanged: (v) => setState(() => c.color = v)),
            const Section('Icon'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < categoryIcons.length; i++)
                IconButton.filledTonal(
                  isSelected: c.icon == i,
                  onPressed: () => setState(() => c.icon = i),
                  icon: Icon(categoryIcons[i], color: c.icon == i ? Color(c.color) : null),
                ),
            ]),
            const SizedBox(height: 16),
            FilledButton(onPressed: save, child: const Text('Save')),
            if (widget.existing != null)
              TextButton(
                onPressed: () {
                  c.archived = !c.archived;
                  context.appRead.save(c);
                  Navigator.pop(context);
                },
                child: Text(c.archived ? 'Unarchive' : 'Archive (history is kept)'),
              ),
            if (widget.existing != null) DeleteButton(what: c.name, body: _catDeleteBody, toDelete: () => [c], pops: 2),
          ]),
        ),
      );
}

class ScheduleEditor extends StatefulWidget {
  final IncomeSchedule? existing;
  const ScheduleEditor({super.key, this.existing});
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final form = GlobalKey<FormState>();
  late final s = widget.existing ?? IncomeSchedule(id: newId(), name: 'Paycheck', frequency: 'weekly', anchorDate: today());
  late final name = TextEditingController(text: s.name);
  late final amount = TextEditingController(text: s.expectedCents == 0 ? '' : centsToInput(s.expectedCents));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Income schedule', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name (e.g. Job)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: s.frequency,
              decoration: const InputDecoration(labelText: 'How often'),
              items: [for (final f in IncomeSchedule.frequencies) DropdownMenuItem(value: f, child: Text(freqLabel(f)))],
              onChanged: (v) => setState(() => s.frequency = v!),
            ),
            const SizedBox(height: 12),
            DateField(value: s.anchorDate, label: 'A payday (past or next)', onChanged: (d) => setState(() => s.anchorDate = d!)),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Typical amount (estimate, used for forecasts)', prefixText: '\$ '),
              validator: (v) => (v ?? '').isEmpty || (parseCents(v!) ?? -1) >= 0 ? null : 'Invalid',
            ),
            const SizedBox(height: 4),
            Text('Paychecks can vary: you always log the real amount on payday.', style: context.tt.bodySmall),
            SwitchListTile(value: s.active, onChanged: (v) => setState(() => s.active = v), title: const Text('Active')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                s
                  ..name = name.text.trim().isEmpty ? 'Paycheck' : name.text.trim()
                  ..expectedCents = parseCents(amount.text) ?? 0;
                context.appRead.save(s);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
            if (widget.existing != null)
              TextButton(
                onPressed: () {
                  s.deleted = true;
                  context.appRead.save(s);
                  Navigator.pop(context);
                },
                child: const Text('Remove schedule'),
              ),
          ]),
        ),
      );
}
