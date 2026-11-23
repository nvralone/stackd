import 'package:material_ui/material_ui.dart';

import '../../clover/brain.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/allocation.dart';
import '../../domain/bills.dart';
import '../../domain/finance.dart';
import '../app.dart';
import '../common.dart';
import '../theme.dart';
import '../sheets/money_sheets.dart';
import 'activity.dart';
import 'home.dart';

Color occColor(OccStatus s) => switch (s) {
      OccStatus.overdue => Accents.danger,
      OccStatus.dueSoon => Accents.warn,
      OccStatus.partial => Accents.income,
      OccStatus.paid => Accents.savings,
      _ => Colors.grey,
    };

class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final upcoming = d.upcomingBills(days: 30);
    final recurring = d.bills.where((b) => !b.archived && !b.isDebt).toList();
    final debts = d.bills.where((b) => !b.archived && b.isDebt).toList();
    return Scaffold(
      appBar: PageBar('Bills', actions: [IconButton(tooltip: 'New bill or debt', onPressed: () => sheet(context, const BillEditor()), icon: const Icon(Icons.add))]),
      body: PageBody(children: [
        Row(children: [
          Expanded(child: Stat('Due before payday', d.reservedForBills, icon: Icons.event_rounded, color: Accents.warn)),
          const SizedBox(width: 12),
          Expanded(child: Stat('Next 30 days', upcoming.where((o) => !o.bill.incoming).fold(0, (s, o) => s + o.remainingCents), icon: Icons.date_range_rounded)),
        ]),
        const Section('Next 30 days'),
        if (upcoming.isEmpty) const Panel(child: Text('Nothing due. Nice.')),
        if (upcoming.isNotEmpty) Panel(padding: EdgeInsets.zero, child: Column(children: [for (final o in upcoming) OccurrenceTile(o)])),
        const Section('Recurring & one-time'),
        if (recurring.isEmpty) const Empty('Add rent, insurance, subscriptions...', icon: Icons.event_repeat_rounded),
        for (final b in recurring) _BillTile(b),
        const Section('Debts'),
        if (debts.isEmpty) const Empty('Track Cash App Borrow, loans, or money between friends.', icon: Icons.handshake_rounded),
        for (final b in debts) _BillTile(b),
      ]),
    );
  }
}

class _BillTile extends StatelessWidget {
  final Bill b;
  const _BillTile(this.b);
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final next = nextOpen(b, d.ledger, d.overrides, now: d.now);
    final remaining = remainingOwed(b, d.ledger);
    final owed = totalOwed(b);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillDetail(b.id))),
        leading: Icon(b.incoming ? Icons.call_received_rounded : (b.isDebt ? Icons.handshake_rounded : Icons.event_repeat_rounded),
            color: b.incoming ? Accents.income : null),
        title: Text(b.name),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m(b.amountCents)} · ${freqLabel(b.frequency)}${next != null ? ' · next ${prettyDate(next.due)}' : ' · all paid'}'),
          if (remaining != null && owed != null && b.isDebt) ...[
            const SizedBox(height: 4),
            Bar(owed - remaining, owed, color: Accents.savings),
            Text('${m(remaining)} ${b.incoming ? 'still owed to you' : 'left to pay'}', style: context.tt.labelSmall),
          ],
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (next == null) const Icon(Icons.check_circle, color: Accents.savings) else if (context.wide) Chip(label: Text(occLabel(next)), side: BorderSide(color: occColor(next.status))),
          billMenu(context, b),
        ]),
      ),
    );
  }
}

const _billDeleteBody = 'Its schedule and reminders go away. Payments you already recorded stay in your history and balances.';

Widget billMenu(BuildContext context, Bill b, {bool inDetail = false}) => ItemMenu(
      what: b.name,
      deleteBody: _billDeleteBody,
      onEdit: () => sheet(context, BillEditor(existing: b)),
      toDelete: () => [b, ...context.appRead.data.overrides.where((o) => o.billId == b.id)],
      afterDelete: inDetail ? () => Navigator.pop(context) : null,
      extra: [if (!b.isDebt) ('Move to Budget (spending category)', Icons.pie_chart_rounded, () => moveBillToBudget(context, b, popAfter: inDetail))],
    );

/// Turns a bill that is really everyday spending into a budget category with a matching limit.
Future<void> moveBillToBudget(BuildContext context, Bill b, {bool popAfter = false}) async {
  final app = context.appRead;
  final monthly = b.frequency == 'monthly' || b.frequency == 'yearly' || b.frequency == 'once';
  final limit = switch (b.frequency) { 'biweekly' => b.amountCents ~/ 2, 'yearly' => b.amountCents ~/ 12, _ => b.amountCents };
  final existing = app.data.categories.where((c) => c.name.toLowerCase() == b.name.toLowerCase()).firstOrNull;
  final ok = await confirm(context, 'Move "${b.name}" to Budget?',
      '${existing != null ? 'Your existing "${existing.name}" category gets' : 'A new category gets'} a ${monthly ? 'monthly' : 'weekly'} limit of ${m(limit)}, and the bill is deleted. Recorded payments stay in history.',
      ok: 'Move');
  if (!ok) return;
  final c = existing ?? Category(id: newId(), name: b.name, color: pickColors[app.data.categories.length % pickColors.length], sort: app.data.categories.length);
  c
    ..limitCents = limit
    ..period = monthly ? 'monthly' : 'weekly'
    ..archived = false;
  app.save(c);
  app.deleteItems([b]);
  if (popAfter && context.mounted) Navigator.pop(context);
  if (context.mounted) context.toast('Moved to Budget.');
}

/// What "Reserved for bills" is holding money for, with quick paid / skip / move actions.
class ReservedSheet extends StatelessWidget {
  const ReservedSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final list = d.upcomingBills(days: d.daysUntilHorizon).where((o) => !o.bill.incoming).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Reserved for bills: ${m(d.reservedForBills)}', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Money set aside for these until ${d.nextPayday != null ? 'payday ${prettyDate(d.nextPayday!)}' : 'the next 2 weeks'}. '
            'Tap one to mark it paid, skip it, move its date, or edit/delete the bill. That frees the money right away.',
            style: context.tt.bodySmall),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.mail_rounded, color: Accents.warn),
            title: const Text('Bill envelope (for later bills)'),
            subtitle: Text('${m(d.goals.where((g) => g.name == billSavingsName && !g.archived).fold(0, (s, g) => s + d.ledger.goalBalance(g.id)))} saved · recommended now: ${m(billSavingsNeed(d))}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => sheet(context, const BillEnvelopeSheet()),
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing reserved before payday. All clear.')),
        for (final o in list) OccurrenceTile(o),
      ]),
    );
  }
}

class OccurrenceTile extends StatelessWidget {
  final BillOccurrence o;
  const OccurrenceTile(this.o, {super.key});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () => sheet(context, PayBill(o: o)),
        leading: CircleAvatar(
          backgroundColor: occColor(o.status).withValues(alpha: 0.2),
          child: Text('${o.due.day}', style: TextStyle(fontWeight: FontWeight.w800, color: occColor(o.status))),
        ),
        title: Text(o.bill.name),
        subtitle: Text('${occLabel(o)} · ${weekdayNames[o.due.weekday - 1]} ${prettyDate(o.due)}${o.paidCents > 0 ? ' · ${m(o.paidCents)} paid' : ''}'
            '${o.setAside ? ' · money set aside ✓' : ''}${o.isLast ? ' · last one, cancel it!' : ''}'),
        trailing: Money(o.remainingCents, color: o.bill.incoming ? Accents.income : null),
      );
}

class BillDetail extends StatelessWidget {
  final String id;
  const BillDetail(this.id, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final b = d.bill(id);
    if (b == null) return const Scaffold(body: Empty('Bill not found'));
    final horizon = addDays(d.todayDate, b.frequency == 'yearly' ? 800 : 120);
    final occ = occurrences(b, d.ledger, d.overrides, horizon, now: d.now);
    final payments = d.ledger.all.where((e) => e.billId == id && e.goalId == null).toList()..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    final remaining = remainingOwed(b, d.ledger);
    return Scaffold(
      appBar: AppBar(title: Text(b.name), actions: [billMenu(context, b, inDetail: true)]),
      body: PageBody(children: [
        Panel(
          child: Wrap(spacing: 24, runSpacing: 10, children: [
            _kv(context, 'Per payment', m(b.amountCents)),
            _kv(context, 'Schedule', freqLabel(b.frequency)),
            if (paymentCountOf(b) != null) _kv(context, 'Payments', '${paymentCountOf(b)}'),
            if (b.principalCents != null) _kv(context, 'Principal', m(b.principalCents!)),
            if (b.feeCents > 0) _kv(context, 'Fees/interest', m(b.feeCents)),
            if (remaining != null) _kv(context, b.incoming ? 'Still owed to you' : 'Remaining', m(remaining)),
            _kv(context, 'Paid so far', m(d.ledger.paidForBill(b.id))),
            if (b.counterparty != null) _kv(context, b.incoming ? 'Borrower' : 'Lender', b.counterparty!),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Scheduled payments reduce safe-to-spend. Balances only change when you record a payment.', style: context.tt.bodySmall),
        const Section('Schedule'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final o in occ)
              ListTile(
                dense: true,
                leading: Icon(o.status == OccStatus.paid ? Icons.check_circle : (o.status == OccStatus.skipped ? Icons.block : Icons.radio_button_unchecked),
                    color: occColor(o.status)),
                title: Text('#${o.index + 1} · ${prettyDate(o.due)} ${o.due.year}'),
                subtitle: Text(occLabel(o) + (o.paidCents > 0 ? ' · ${m(o.paidCents)} of ${m(o.amountCents)}' : '')),
                trailing: Money(o.amountCents, size: 14),
                onTap: o.status == OccStatus.paid ? null : () => sheet(context, PayBill(o: o)),
              ),
          ]),
        ),
        const Section('Payment history'),
        if (payments.isEmpty) const Empty('No payments recorded yet.'),
        for (final e in payments)
          ListTile(
            onTap: () => sheet(context, EventDetail(e)),
            title: Text('${kindLabel(e.kind)}${e.kind != 'reversal' ? ' · payment ${(e.billOccurrence ?? 0) + 1}' : ''}',
                style: TextStyle(decoration: d.ledger.isReversed(e.id) ? TextDecoration.lineThrough : null)),
            subtitle: Text(prettyDate(e.occurredOn)),
            trailing: Money(e.amountCents, size: 14),
          ),
      ]),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: c.tt.labelSmall),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ]);
}

/// Record a (partial / early / late) payment, or reschedule / skip the occurrence.
class PayBill extends StatefulWidget {
  final BillOccurrence o;
  const PayBill({super.key, required this.o});
  @override
  State<PayBill> createState() => _PayBillState();
}

class _PayBillState extends State<PayBill> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(text: centsToInput(widget.o.remainingCents));
  final String eventId = newId();
  late String? account = widget.o.bill.accountId ?? context.appRead.data.accounts.where((a) => !a.archived).firstOrNull?.id;
  late DateTime date = context.appRead.data.todayDate;
  late final SavingsGoal? billVault = context.appRead.data.goals.where((g) => g.name == billSavingsName && !g.archived).firstOrNull;
  late bool fromSavings = _usable(context.appRead.data) > 0;
  /// Envelope money this bill may use: what's set aside for it plus unassigned money (never other bills' money).
  int _usable(FinanceData d) => billVault == null ? 0 : (d.billEarmarks[widget.o.bill.id] ?? 0) + d.billEnvelopeUnassigned;
  bool outsideCash = false; // paid with money that was never in the app

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    final b = o.bill;
    final saved = _usable(context.app.data);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(b.incoming ? 'Record repayment received' : 'Record payment', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('${b.name} · payment ${o.index + 1} · due ${prettyDate(o.due)}'),
          const SizedBox(height: 12),
          AmountField(amount, label: 'Amount (partial is fine)'),
          const SizedBox(height: 12),
          AccountPicker(value: account, label: b.incoming ? 'Received into' : 'Paid from', onChanged: (v) => setState(() => account = v)),
          const SizedBox(height: 12),
          DateField(value: date, label: 'Paid on', onChanged: (d) => setState(() => date = d!)),
          if (!b.incoming)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: outsideCash,
              onChanged: (v) => setState(() => outsideCash = v!),
              title: const Text('Paid with cash not in the app'),
              subtitle: const Text('Marks it paid without taking money out of your accounts.'),
            ),
          if (!b.incoming && saved > 0 && !outsideCash)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: fromSavings,
              onChanged: (v) => setState(() => fromSavings = v!),
              title: const Text('Use my Bill savings'),
              subtitle: Text('${m(saved)} in the Bill envelope for this bill. It comes out of the envelope, so your free money stays the same.'),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final app = context.appRead;
              final cents = parseCents(amount.text)!;
              if (cents > o.remainingCents &&
                  !await confirm(context, 'More than due', 'This is more than the ${m(o.remainingCents)} due. The extra will not apply to later payments. Continue?')) {
                return;
              }
              final e = app.event(
                  id: eventId, kind: b.incoming ? 'loan_in' : 'bill_payment', amountCents: cents, accountId: account,
                  categoryId: b.incoming ? null : b.categoryId, billId: b.id, billOccurrence: o.index, on: date, groupId: eventId);
              final useSaved = fromSavings && !outsideCash && billVault != null && !b.incoming ? (cents < saved ? cents : saved) : 0;
              app.record([
                e,
                if (outsideCash && account != null)
                  app.event(kind: 'adjustment', amountCents: cents, accountId: account, on: date, groupId: eventId, note: 'Paid with cash not in the app'),
                if (useSaved > 0)
                  app.event(kind: 'goal_withdraw', amountCents: useSaved, goalId: billVault!.id, billId: b.id, reason: 'planned', on: date, groupId: eventId, note: 'Paid ${b.name}'),
              ], trigger: BillPaid(e));
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(b.incoming ? 'Confirm received' : 'Confirm paid'),
          ),
          if (!b.incoming) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: Icon(o.setAside ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
              label: Text(o.setAside ? 'Money set aside (tap to undo)' : 'I have the money, not paid yet'),
              onPressed: () {
                final app = context.appRead;
                final ex = app.data.overrides.where((x) => x.billId == b.id && x.occurrence == o.index).firstOrNull;
                app.save((ex ?? BillOverride(id: newId(), billId: b.id, occurrence: o.index))..setAside = !o.setAside);
                Navigator.pop(context);
                context.toast(o.setAside ? 'Unmarked.' : 'Marked: money is ready. Tap "Confirm paid" when you actually pay.');
              },
            ),
          ],
          if (o.isLast)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('This is the last payment. Remember to cancel it before it renews!', style: TextStyle(color: Accents.warn, fontWeight: FontWeight.w700)),
            ),
          const Divider(height: 28),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_calendar_rounded),
            label: const Text('Reschedule this payment'),
            onPressed: () async {
              final app = context.appRead;
              final picked = await showDatePicker(context: context, initialDate: o.due, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked == null) return;
              final ex = app.data.overrides.where((x) => x.billId == b.id && x.occurrence == o.index).firstOrNull;
              app.save((ex ?? BillOverride(id: newId(), billId: b.id, occurrence: o.index))..dueOn = dateOnly(picked)..skipped = false);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          TextButton(
            onPressed: () async {
              final app = context.appRead;
              if (!await confirm(context, 'Skip this payment?', 'It will no longer be reserved or reminded. Undo by rescheduling it.')) return;
              final ex = app.data.overrides.where((x) => x.billId == b.id && x.occurrence == o.index).firstOrNull;
              app.save((ex ?? BillOverride(id: newId(), billId: b.id, occurrence: o.index))..skipped = true);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Skip this payment'),
          ),
          const Divider(height: 28),
          Text('Manage this bill', style: context.tt.labelLarge),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Edit'),
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                sheet(nav.context, BillEditor(existing: b));
              },
            ),
            if (!b.isDebt)
              TextButton.icon(
                icon: const Icon(Icons.pie_chart_rounded),
                label: const Text('Move to Budget'),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  moveBillToBudget(nav.context, b);
                },
              ),
            if (b.kind == 'recurring' && !o.isLast)
              TextButton.icon(
                icon: const Icon(Icons.event_busy_rounded),
                label: const Text('Make this the last payment'),
                onPressed: () async {
                  final app = context.appRead;
                  final nav = Navigator.of(context);
                  if (!await confirm(context, 'End ${b.name} after this one?',
                      'Payments stop after ${prettyDate(o.due)}. You\'ll get a reminder to cancel it before then.', ok: 'End after this')) {
                    return;
                  }
                  app.save(b..paymentCount = o.index + 1);
                  nav.pop();
                },
              ),
            DeleteButton(what: b.name, body: _billDeleteBody, toDelete: () => [b]),
          ]),
        ]),
      ),
    );
  }
}

class BillEditor extends StatefulWidget {
  final Bill? existing;
  const BillEditor({super.key, this.existing});
  @override
  State<BillEditor> createState() => _BillEditorState();
}

class _BillEditorState extends State<BillEditor> {
  final form = GlobalKey<FormState>();
  late final b = widget.existing ?? Bill(id: newId(), name: '', amountCents: 0, firstDue: today());
  late final name = TextEditingController(text: b.name), who = TextEditingController(text: b.counterparty ?? '');
  late final amount = TextEditingController(text: b.amountCents == 0 ? '' : centsToInput(b.amountCents));
  late final principal = TextEditingController(text: b.principalCents == null ? '' : centsToInput(b.principalCents!));
  late final fee = TextEditingController(text: b.feeCents == 0 ? '' : centsToInput(b.feeCents));
  late final count = TextEditingController(text: b.paymentCount?.toString() ?? '');
  bool recordStart = true;
  String? startAccount;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'New bill or debt' : 'Edit', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in const {'recurring': 'Recurring bill', 'one_time': 'One-time bill', 'debt_owed': 'I borrowed', 'debt_lent': 'I lent'}.entries)
              ChoiceChip(
                  label: Text(k.value),
                  selected: b.kind == k.key,
                  onSelected: isNew
                      ? (_) => setState(() {
                            b.kind = k.key;
                            if (k.key == 'one_time') b.frequency = 'once';
                            if (k.key != 'one_time' && b.frequency == 'once') b.frequency = 'weekly';
                          })
                      : null),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: name, decoration: InputDecoration(labelText: b.isDebt ? 'Name (e.g. Cash App Borrow)' : 'Name (e.g. Rent)'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Name it' : null),
          if (b.isDebt) ...[
            const SizedBox(height: 12),
            TextFormField(controller: who, decoration: InputDecoration(labelText: b.kind == 'debt_lent' ? 'Who owes you' : 'Lender (optional)')),
            const SizedBox(height: 12),
            AmountField(principal, label: b.kind == 'debt_lent' ? 'Amount lent' : 'Amount borrowed'),
            const SizedBox(height: 12),
            TextFormField(controller: fee, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Fees or interest (total, optional)', prefixText: '\$ ')),
          ],
          const SizedBox(height: 12),
          AmountField(amount, label: b.isDebt ? 'Each payment' : 'Amount'),
          const SizedBox(height: 12),
          if (b.kind != 'one_time')
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: b.frequency,
              decoration: const InputDecoration(labelText: 'How often'),
              items: [for (final f in Bill.frequencies.where((f) => f != 'once' || b.isDebt)) DropdownMenuItem(value: f, child: Text(freqLabel(f)))],
              onChanged: (v) => setState(() => b.frequency = v!),
            ),
          const SizedBox(height: 12),
          DateField(value: b.firstDue, label: b.kind == 'one_time' ? 'Due date' : 'First (next) due date', onChanged: (d) => setState(() => b.firstDue = d!)),
          if (b.kind == 'recurring') ...[
            const SizedBox(height: 12),
            TextFormField(controller: count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of payments (blank = ongoing)')),
          ],
          if (!b.incoming) ...[
            const SizedBox(height: 12),
            CategoryPicker(value: b.categoryId, required: false, onChanged: (v) => setState(() => b.categoryId = v)),
          ],
          const SizedBox(height: 12),
          AccountPicker(value: b.accountId, label: 'Usual account (optional)', onChanged: (v) => setState(() => b.accountId = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: b.reminderDays,
            decoration: const InputDecoration(labelText: 'Remind me'),
            items: [for (final n in const [0, 1, 2, 3, 5, 7]) DropdownMenuItem(value: n, child: Text(n == 0 ? 'On the due date' : '$n day${n > 1 ? 's' : ''} before'))],
            onChanged: (v) => setState(() => b.reminderDays = v!),
          ),
          if (isNew && b.isDebt) ...[
            SwitchListTile(
              value: recordStart,
              onChanged: (v) => setState(() => recordStart = v),
              title: Text(b.kind == 'debt_lent' ? 'Record the money I gave' : 'Record the money I received'),
              subtitle: Text(b.kind == 'debt_lent' ? 'Takes it out of an account (not spending)' : 'Adds it to an account (not earned income)'),
            ),
            if (recordStart) AccountPicker(value: startAccount, onChanged: (v) => setState(() => startAccount = v)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
          if (!isNew)
            TextButton(
              onPressed: () {
                b.archived = !b.archived;
                context.appRead.save(b);
                Navigator.pop(context);
              },
              child: Text(b.archived ? 'Unarchive' : 'Archive (stops reminders, keeps history)'),
            ),
          if (!isNew) DeleteButton(what: b.name, body: _billDeleteBody, toDelete: () => [b], pops: 2),
        ]),
      ),
    );
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    final app = context.appRead;
    b
      ..name = name.text.trim()
      ..amountCents = parseCents(amount.text)!
      ..counterparty = who.text.trim().isEmpty ? null : who.text.trim()
      ..principalCents = b.isDebt ? parseCents(principal.text) : null
      ..feeCents = b.isDebt ? (parseCents(fee.text) ?? 0).abs() : 0
      ..paymentCount = b.kind == 'recurring' ? int.tryParse(count.text.trim()) : null;
    if (b.kind == 'one_time') b.frequency = 'once';
    final isNew = widget.existing == null;
    // A new recurring bill dated in the past would show every missed date as overdue.
    // Treat past dates as already handled and start from the next upcoming one.
    final rolled = isNew && b.kind == 'recurring' ? rollForward(b.firstDue, b.frequency, today()) : null;
    if (rolled != null && rolled != b.firstDue) {
      b.firstDue = rolled;
      context.toast('Starts ${prettyDate(rolled)} (earlier dates count as already paid).');
    }
    if (isNew && b.isDebt && recordStart && startAccount != null && b.principalCents != null) {
      app.record([
        b.kind == 'debt_lent'
            ? app.event(kind: 'loan_out', amountCents: b.principalCents!, accountId: startAccount, billId: b.id, note: 'Lent: ${b.name}')
            : app.event(kind: 'income', incomeSource: 'loan', amountCents: b.principalCents!, accountId: startAccount, billId: b.id, note: 'Borrowed: ${b.name}'),
      ], also: [b]);
    } else {
      app.save(b);
    }
    Navigator.pop(context);
  }
}
