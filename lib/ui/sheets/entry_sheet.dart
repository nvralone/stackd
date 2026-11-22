// Quick Add / edit for expenses, income, transfers, refunds and adjustments.
import 'package:material_ui/material_ui.dart';

import '../../clover/brain.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/allocation.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'allocation_sheet.dart';

Future<void> openQuickAdd(BuildContext context, {String kind = 'expense', LedgerEvent? editing, String? categoryId, String? tripId, int? cents, String? note}) async {
  final app = context.appRead;
  if (app.data.accounts.isEmpty) {
    context.toast('Add a money account first (Settings > Accounts).');
    return;
  }
  await sheet(context, EntrySheet(kind: editing?.kind ?? kind, editing: editing, categoryId: categoryId, tripId: tripId, cents: cents, note: note));
}

class EntrySheet extends StatefulWidget {
  final String kind;
  final LedgerEvent? editing;
  final String? categoryId, tripId, note;
  final int? cents;
  const EntrySheet({super.key, required this.kind, this.editing, this.categoryId, this.tripId, this.cents, this.note});
  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  final form = GlobalKey<FormState>();
  late String kind = widget.kind;
  // Generated once per sheet: a double tap on Save produces the same id and is ignored as a duplicate.
  final String eventId = newId();
  late final amount = TextEditingController(text: widget.editing != null ? centsToInput(widget.editing!.amountCents.abs()) : (widget.cents != null ? centsToInput(widget.cents!) : ''));
  late final note = TextEditingController(text: widget.editing?.note ?? widget.note ?? '');
  late String? account = widget.editing?.accountId ?? _defaultAccount();
  late String? toAccount = widget.editing?.toAccountId;
  late String? category = widget.editing?.categoryId ?? widget.categoryId;
  late String source = widget.editing?.incomeSource ?? 'paycheck';
  late String? trip = widget.editing?.tripId ?? widget.tripId;
  late DateTime date = widget.editing?.occurredOn ?? today();
  bool adjustUp = true;
  bool saving = false;

  String? _defaultAccount() {
    final a = context.appRead.data.accounts.where((a) => !a.archived);
    return a.isEmpty ? null : a.first.id;
  }

  bool get editing => widget.editing != null;

  void save() {
    if (saving || !form.currentState!.validate()) return;
    saving = true;
    final app = context.appRead;
    var cents = parseCents(amount.text)!.abs();
    if (kind == 'adjustment' && !adjustUp) cents = -cents;
    if (editing) {
      app.edit(
          widget.editing!,
          widget.editing!.replacement(
              newId: eventId, amountCents: cents, on: date, accountId: account, toAccountId: toAccount,
              categoryId: category, note: note.text.trim().isEmpty ? null : note.text.trim()));
      Navigator.pop(context);
      context.toast('Updated. The original is kept in history.');
      return;
    }
    final group = newId();
    // Proposal is computed BEFORE the income is recorded so bills coverage is judged on current free money.
    final proposal = kind == 'income' && source == 'paycheck' ? suggestPaycheck(app.data, cents) : null;
    final e = app.event(
      id: eventId,
      kind: kind,
      amountCents: cents,
      on: date,
      accountId: account,
      toAccountId: kind == 'transfer' ? toAccount : null,
      categoryId: kind == 'expense' || kind == 'refund' ? category : null,
      incomeSource: kind == 'income' ? source : null,
      tripId: kind == 'expense' ? trip : null,
      groupId: group,
      note: note.text,
    );
    final tripEntry = kind == 'expense' && trip != null
        ? TripEntry(id: newId(), tripId: trip!, kind: 'expense', amountCents: cents, occurredOn: date, ledgerEventId: e.id, note: note.text.trim().isEmpty ? null : note.text.trim())
        : null;
    final CloverTrigger? trigger = switch (kind) {
      'expense' => ExpenseLogged(e),
      'income' || 'refund' => IncomeLogged(e),
      'transfer' => TransferLogged(e),
      _ => null,
    };
    app.record([e], trigger: trigger, also: [?tripEntry]);
    final nav = Navigator.of(context);
    nav.pop();
    if (proposal != null && proposal.lines.any((l) => l.kind == TargetKind.goal)) {
      sheet(nav.context, AllocationSheet(title: 'Split your paycheck', amount: cents, groupId: group, date: date, suggested: proposal));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.app.data;
    final trips = data.trips.where((t) => !t.archived).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(editing ? 'Edit ${kindLabel(kind).toLowerCase()}' : 'Quick Add', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (!editing)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.remove_circle_outline)),
                  ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.add_circle_outline)),
                  ButtonSegment(value: 'transfer', label: Text('Transfer'), icon: Icon(Icons.swap_horiz)),
                  ButtonSegment(value: 'refund', label: Text('Refund'), icon: Icon(Icons.undo)),
                  ButtonSegment(value: 'adjustment', label: Text('Adjust'), icon: Icon(Icons.tune)),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
            ),
          const SizedBox(height: 16),
          AmountField(amount, autofocus: !editing),
          if (kind == 'adjustment') ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Add to balance')), ButtonSegment(value: false, label: Text('Remove from balance'))],
              selected: {adjustUp},
              onSelectionChanged: (s) => setState(() => adjustUp = s.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Adjustments correct a balance to match reality. They are not income or spending.', style: context.tt.bodySmall),
            ),
          ],
          const SizedBox(height: 12),
          if (kind == 'expense' || kind == 'refund') ...[
            CategoryPicker(value: category, onChanged: (v) => setState(() => category = v)),
            const SizedBox(height: 12),
          ],
          if (kind == 'income') ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: source,
              decoration: const InputDecoration(labelText: 'Source'),
              items: [for (final s in LedgerEvent.incomeSources) DropdownMenuItem(value: s, child: Text(sourceLabel(s)))],
              onChanged: (v) => setState(() => source = v!),
            ),
            if (source == 'loan')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Borrowed money adds to your balance but is not counted as earned income. Add the repayment plan under Bills.',
                    style: context.tt.bodySmall),
              ),
            const SizedBox(height: 12),
          ],
          AccountPicker(value: account, label: kind == 'transfer' ? 'From account' : 'Account', onChanged: (v) => setState(() => account = v)),
          if (kind == 'transfer') ...[
            const SizedBox(height: 12),
            AccountPicker(value: toAccount, label: 'To account', exclude: account, onChanged: (v) => setState(() => toAccount = v)),
          ],
          const SizedBox(height: 12),
          DateField(value: date, onChanged: (d) => setState(() => date = d!)),
          if (kind == 'expense' && trips.isNotEmpty && !editing) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: trip,
              decoration: const InputDecoration(labelText: 'Trip (optional)'),
              items: [const DropdownMenuItem(value: null, child: Text('Not trip-related')), for (final t in trips) DropdownMenuItem(value: t.id, child: Text(t.name))],
              onChanged: (v) => setState(() => trip = v),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)'), maxLength: 500),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: save, icon: const Icon(Icons.check_rounded), label: Text(editing ? 'Save changes' : 'Save')),
          if (!editing) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Accents.income, minimumSize: const Size(48, 48)),
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                sheet(nav.context, const ExtraMoneySheet());
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Got extra money? Split it'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Extra Money: record the income/refund, then choose Suggested / Manual / Single destination.
class ExtraMoneySheet extends StatefulWidget {
  const ExtraMoneySheet({super.key});
  @override
  State<ExtraMoneySheet> createState() => _ExtraMoneySheetState();
}

class _ExtraMoneySheetState extends State<ExtraMoneySheet> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController();
  final String eventId = newId(), group = newId();
  String source = 'sale';
  String? account, category;
  DateTime date = today();

  static const sources = ['sale', 'side_job', 'tip', 'gift', 'refund', 'other'];

  @override
  void initState() {
    super.initState();
    account = context.appRead.data.accounts.where((a) => !a.archived).firstOrNull?.id;
  }

  void next() {
    if (!form.currentState!.validate()) return;
    final app = context.appRead;
    final cents = parseCents(amount.text)!;
    final proposal = suggestExtra(app.data, cents);
    final refund = source == 'refund';
    final e = app.event(
        id: eventId, kind: refund ? 'refund' : 'income', amountCents: cents, on: date, accountId: account,
        categoryId: refund ? category : null, incomeSource: refund ? null : source, groupId: group, note: note.text);
    app.record([e], trigger: IncomeLogged(e, extra: true));
    final nav = Navigator.of(context);
    nav.pop();
    sheet(nav.context, AllocationSheet(title: 'Split ${m(cents)}', amount: cents, groupId: group, date: date, suggested: proposal, allowModes: true));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Extra Money', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: Accents.income)),
            Text('Sold something? Got tips, a gift, a refund? Record it, then decide where it goes.', style: context.tt.bodyMedium),
            const SizedBox(height: 16),
            AmountField(amount, autofocus: true),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in sources)
                ChoiceChip(
                  label: Text(s == 'refund' ? 'Refund' : sourceLabel(s)),
                  selected: source == s,
                  onSelected: (_) => setState(() => source = s),
                ),
            ]),
            if (source == 'refund') ...[
              const SizedBox(height: 6),
              Text('Refunds reduce spending in their category instead of counting as earned income.', style: context.tt.bodySmall),
              const SizedBox(height: 8),
              CategoryPicker(value: category, onChanged: (v) => setState(() => category = v)),
            ],
            const SizedBox(height: 12),
            AccountPicker(value: account, onChanged: (v) => setState(() => account = v)),
            const SizedBox(height: 12),
            DateField(value: date, onChanged: (d) => setState(() => date = d!)),
            const SizedBox(height: 12),
            TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Source details / notes (optional)')),
            const SizedBox(height: 16),
            FilledButton(onPressed: next, child: const Text('Next: choose where it goes')),
          ]),
        ),
      );
}
