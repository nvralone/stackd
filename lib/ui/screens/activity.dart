import 'package:material_ui/material_ui.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/finance.dart';
import '../app.dart';
import '../common.dart';
import '../sheets/entry_sheet.dart';
import '../theme.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String query = '';
  String filter = 'all';
  bool showReversed = false;

  static const filters = {
    'all': 'All',
    'expense': 'Expenses',
    'income': 'Income',
    'transfer': 'Transfers',
    'savings': 'Savings',
    'bill_payment': 'Bills',
    'refund': 'Refunds',
    'adjustment': 'Adjustments',
  };

  bool matches(LedgerEvent e, FinanceData f) {
    if (e.kind == 'reversal' && !showReversed) return false;
    if (!showReversed && f.ledger.isReversed(e.id)) return false;
    if (filter == 'savings' && !e.kind.startsWith('goal_')) return false;
    if (filter == 'adjustment' && !(e.kind == 'adjustment' || e.kind == 'opening')) return false;
    if (!{'all', 'savings', 'adjustment'}.contains(filter) && e.kind != filter) return false;
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final cents = parseCents(query);
    return (e.note?.toLowerCase().contains(q) ?? false) ||
        (f.category(e.categoryId)?.name.toLowerCase().contains(q) ?? false) ||
        (f.account(e.accountId)?.name.toLowerCase().contains(q) ?? false) ||
        (f.goal(e.goalId)?.name.toLowerCase().contains(q) ?? false) ||
        (f.bill(e.billId)?.name.toLowerCase().contains(q) ?? false) ||
        kindLabel(e.kind).toLowerCase().contains(q) ||
        (cents != null && e.amountCents.abs() == cents.abs());
  }

  @override
  Widget build(BuildContext context) {
    final f = context.app.data;
    final events = f.ledger.all.where((e) => matches(e, f)).toList()
      ..sort((a, b) {
        final c = b.occurredOn.compareTo(a.occurredOn);
        return c != 0 ? c : (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
    final rows = <Widget>[];
    DateTime? last;
    for (final e in events.take(500)) {
      if (last != e.occurredOn) {
        last = e.occurredOn;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text('${weekdayNames[e.occurredOn.weekday - 1]}, ${prettyDate(e.occurredOn)} ${e.occurredOn.year}',
              style: context.tt.labelLarge?.copyWith(color: context.cs.onSurfaceVariant)),
        ));
      }
      rows.add(EventTile(e));
    }
    return Scaffold(
      appBar: const PageBar('Activity'),
      body: PageBody(children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search notes, categories, accounts, amounts'),
          onChanged: (v) => setState(() => query = v.trim()),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final e in filters.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(e.value), selected: filter == e.key, onSelected: (_) => setState(() => filter = e.key)),
              ),
            FilterChip(label: const Text('Show reversed'), selected: showReversed, onSelected: (v) => setState(() => showReversed = v)),
          ]),
        ),
        if (rows.isEmpty) const Empty('No transactions match.', icon: Icons.receipt_long_rounded) else ...rows,
      ]),
    );
  }
}

class EventTile extends StatelessWidget {
  final LedgerEvent e;
  const EventTile(this.e, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final reversed = d.ledger.isReversed(e.id) || e.kind == 'reversal';
    final cat = d.category(e.categoryId);
    final title = switch (e.kind) {
      'expense' || 'refund' => cat?.name ?? 'Uncategorized',
      'income' => sourceLabel(e.incomeSource),
      'transfer' => '${d.account(e.accountId)?.name ?? '?'} → ${d.account(e.toAccountId)?.name ?? '?'}',
      'goal_deposit' || 'goal_withdraw' => d.goal(e.goalId)?.name ?? 'Vault',
      'bill_payment' || 'loan_in' => d.bill(e.billId)?.name ?? 'Bill',
      _ => kindLabel(e.kind),
    };
    final delta = displayDelta(e);
    final color = switch (e.kind) {
      'income' || 'loan_in' => Accents.income,
      'goal_deposit' => Accents.savings,
      'refund' => Accents.savings,
      _ => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => sheet(context, EventDetail(e)),
        leading: cat != null
            ? CatDot(cat)
            : CircleAvatar(
                backgroundColor: (color ?? context.cs.primary).withValues(alpha: 0.15),
                child: Icon(_icon(e.kind), color: color ?? context.cs.primary, size: 20)),
        title: Text(title, style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null)),
        subtitle: Text([
          kindLabel(e.kind),
          if (e.kind != 'transfer' && d.account(e.accountId) != null) d.account(e.accountId)!.name,
          if (e.reason == 'emergency') 'Emergency',
          if (e.note != null) e.note!,
        ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Money(
          e.kind == 'transfer' || e.kind.startsWith('goal_') || e.kind == 'reversal' ? e.amountCents : delta,
          sign: !(e.kind == 'transfer' || e.kind.startsWith('goal_') || e.kind == 'reversal'),
          color: reversed ? context.cs.onSurfaceVariant : color,
        ),
      ),
    );
  }

  static IconData _icon(String k) => switch (k) {
        'income' => Icons.payments_rounded,
        'transfer' => Icons.swap_horiz_rounded,
        'goal_deposit' => Icons.savings_rounded,
        'goal_withdraw' => Icons.outbox_rounded,
        'bill_payment' => Icons.event_available_rounded,
        'reversal' => Icons.undo_rounded,
        'opening' => Icons.flag_rounded,
        'adjustment' => Icons.tune_rounded,
        'loan_out' => Icons.call_made_rounded,
        'loan_in' => Icons.call_received_rounded,
        _ => Icons.receipt_rounded,
      };
}

class EventDetail extends StatelessWidget {
  final LedgerEvent e;
  const EventDetail(this.e, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final reversed = d.ledger.isReversed(e.id);
    final group = e.groupId == null ? const <LedgerEvent>[] : d.ledger.active.where((x) => x.groupId == e.groupId).toList();
    final editable = const {'expense', 'income', 'refund', 'transfer', 'adjustment'}.contains(e.kind) && !reversed;
    final reversedBy = d.ledger.all.where((x) => x.reversesId == e.id).firstOrNull;
    final original = e.replacesId == null ? null : d.ledger.all.where((x) => x.id == e.replacesId).firstOrNull;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [SizedBox(width: 120, child: Text(k, style: TextStyle(color: context.cs.onSurfaceVariant))), Expanded(child: Text(v))]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(kindLabel(e.kind), style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Money(e.amountCents, size: 32),
        const SizedBox(height: 12),
        row('Date', '${prettyDate(e.occurredOn)} ${e.occurredOn.year}'),
        if (e.accountId != null) row(e.kind == 'transfer' ? 'From' : 'Account', d.account(e.accountId)?.name ?? 'Deleted account'),
        if (e.toAccountId != null) row('To', d.account(e.toAccountId)?.name ?? '?'),
        if (e.categoryId != null) row('Category', d.category(e.categoryId)?.name ?? '?'),
        if (e.goalId != null) row('Vault', d.goal(e.goalId)?.name ?? '?'),
        if (e.billId != null) row('Bill', '${d.bill(e.billId)?.name ?? '?'} (payment ${(e.billOccurrence ?? 0) + 1})'),
        if (e.incomeSource != null) row('Source', sourceLabel(e.incomeSource)),
        if (e.reason != null) row('Reason', e.reason!),
        if (e.note != null) row('Note', e.note!),
        if (e.createdAt != null) row('Synced at', e.createdAt!.toLocal().toString().substring(0, 16)),
        row('Status', reversed ? 'Reversed${reversedBy?.note != null ? ' (${reversedBy!.note})' : ''}' : (e.kind == 'reversal' ? 'Reversal entry' : 'Active')),
        if (original != null) row('Replaces', '${kindLabel(original.kind)} of ${m(original.amountCents)}'),
        const SizedBox(height: 16),
        if (editable)
          FilledButton.tonalIcon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              openQuickAdd(nav.context, editing: e);
            },
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit'),
          ),
        if (!reversed && e.kind != 'reversal') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await confirm(context, 'Reverse this entry?',
                  'Balances will no longer include it. The original stays in your history for auditing.', ok: 'Reverse')) {
                return;
              }
              app.reverse(e);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Reverse (safe delete)'),
          ),
        ],
        if (group.length > 1 && !reversed) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              if (!await confirm(context, 'Undo all ${group.length} linked entries?',
                  'This reverses the income and its split allocations together.', ok: 'Undo all')) {
                return;
              }
              app.reverseGroup(e.groupId!);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.layers_clear_rounded),
            label: Text('Undo linked group (${group.length})'),
          ),
        ],
      ]),
    );
  }
}
