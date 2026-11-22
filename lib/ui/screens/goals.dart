import 'package:material_ui/material_ui.dart';

import '../../clover/brain.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/finance.dart';
import '../../domain/trips.dart';
import '../app.dart';
import '../common.dart';
import '../theme.dart';
import 'activity.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<Map<String, dynamic>> invites = [];

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    final app = context.appRead;
    if (!app.signedIn) return;
    try {
      final rows = await app.client!.from('trip_members').select('trip_id, status, trips(name)').eq('user_id', app.sync!.uid!).eq('status', 'invited');
      if (mounted) setState(() => invites = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _accept(String tripId) async {
    final app = context.appRead;
    try {
      await app.client!.from('trip_members').update({'status': 'accepted'}).eq('trip_id', tripId).eq('user_id', app.sync!.uid!);
      await app.sync!.sync();
      await _loadInvites();
    } catch (e) {
      if (mounted) context.toast('Could not accept: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final goals = d.goalStatuses.where((g) => g.goal.tripId == null).toList();
    final trips = d.trips.where((t) => !t.archived).toList();
    return Scaffold(
      appBar: const PageBar('Goals'),
      body: PageBody(children: [
        for (final i in invites)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              color: Accents.vacation.withValues(alpha: 0.15),
              child: Row(children: [
                const Icon(Icons.group_add_rounded, color: Accents.vacation),
                const SizedBox(width: 10),
                Expanded(child: Text('Trip invite: ${(i['trips'] as Map?)?['name'] ?? 'Shared trip'}')),
                FilledButton(onPressed: () => _accept(i['trip_id'] as String), child: const Text('Join')),
              ]),
            ),
          ),
        Section('Savings vaults', trailing: TextButton.icon(onPressed: () => sheet(context, const GoalEditor()), icon: const Icon(Icons.add), label: const Text('New'))),
        if (goals.isEmpty) const Empty('No vaults yet. Make one for anything you\'re saving toward.', icon: Icons.savings_rounded),
        for (final g in goals) Padding(padding: const EdgeInsets.only(bottom: 10), child: GoalCard(g)),
        Section('Vacations', trailing: TextButton.icon(onPressed: () => sheet(context, const TripEditor()), icon: const Icon(Icons.add), label: const Text('New trip'))),
        if (trips.isEmpty) const Empty('Plan a trip and Clover will help you fund it.', icon: Icons.flight_takeoff_rounded),
        for (final t in trips) Padding(padding: const EdgeInsets.only(bottom: 10), child: TripCard(t)),
        if (d.goals.any((g) => g.archived)) ...[
          const Section('Archived vaults'),
          for (final g in d.goals.where((g) => g.archived))
            ListTile(title: Text(g.name), subtitle: Text(m(d.ledger.goalBalance(g.id))), onTap: () => _open(context, g.id)),
        ],
      ]),
    );
  }
}

void _open(BuildContext context, String id) => Navigator.push(context, MaterialPageRoute(builder: (_) => GoalDetail(id)));

String goalDeleteBody(BuildContext context, SavingsGoal g) {
  final bal = context.appRead.data.ledger.goalBalance(g.id);
  return '${bal > 0 ? 'The ${m(bal)} saved in it goes back to your safe-to-spend money (it never left your accounts). ' : ''}Its history stays in Activity.';
}

Widget goalMenu(BuildContext context, SavingsGoal g, {bool inDetail = false}) => ItemMenu(
      what: g.name,
      deleteBody: goalDeleteBody(context, g),
      onEdit: () => sheet(context, GoalEditor(existing: g)),
      toDelete: () => [g],
      afterDelete: inDetail ? () => Navigator.pop(context) : null,
    );

const _tripDeleteBody = 'Deletes the trip, its budget items and its savings vault. Saved money goes back to safe-to-spend; expenses you recorded stay in Activity.';

List<Entity> tripWithParts(BuildContext context, Trip t) {
  final d = context.appRead.data;
  return [t, ...d.tripItems.where((i) => i.tripId == t.id), ...d.goals.where((g) => g.tripId == t.id)];
}

Widget tripMenu(BuildContext context, Trip t, {bool inDetail = false}) => ItemMenu(
      what: t.name,
      deleteBody: _tripDeleteBody,
      onEdit: () => sheet(context, TripEditor(existing: t)),
      toDelete: () => tripWithParts(context, t),
      afterDelete: inDetail ? () => Navigator.pop(context) : null,
    );

class GoalCard extends StatelessWidget {
  final GoalStatus g;
  final bool menu;
  const GoalCard(this.g, {super.key, this.menu = true});
  @override
  Widget build(BuildContext context) {
    final color = g.goal.tripId != null ? Accents.vacation : Color(g.goal.color);
    return Panel(
      onTap: () => _open(context, g.goal.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(g.goal.tripId != null ? Icons.beach_access_rounded : Icons.savings_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(g.goal.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (g.goal.locked) const Icon(Icons.lock_rounded, size: 16),
          const SizedBox(width: 6),
          Text('${g.pct}%', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          if (menu) goalMenu(context, g.goal),
        ]),
        const SizedBox(height: 10),
        Bar(g.saved, g.goal.goalCents, color: color, height: 10),
        const SizedBox(height: 8),
        Text(
          '${m(g.saved)} saved of ${m(g.goal.goalCents)}'
          '${g.complete ? ' · complete!' : g.forecast != null ? ' · on pace for ${prettyDate(g.forecast!)} ${g.forecast!.year}' : ''}',
          style: context.tt.bodySmall,
        ),
      ]),
    );
  }
}

class GoalDetail extends StatelessWidget {
  final String id;
  const GoalDetail(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final g = d.goal(id);
    if (g == null) return const Scaffold(body: Empty('Vault not found'));
    final s = d.goalStatus(g);
    final history = d.ledger.all.where((e) => e.goalId == id).toList()..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    final planned = g.contributionCents > 0 && g.contributionFreq != 'none';
    return Scaffold(
      appBar: AppBar(title: Text(g.name), actions: [goalMenu(context, g, inDetail: true)]),
      body: PageBody(children: [
        GoalCard(s, menu: false),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () => sheet(context, MoveMoney(goal: g, deposit: true)), icon: const Icon(Icons.add), label: const Text('Deposit'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: s.saved <= 0 ? null : () => sheet(context, MoveMoney(goal: g, deposit: false)), icon: const Icon(Icons.remove), label: const Text('Withdraw'))),
        ]),
        if (d.goals.length > 1 && s.saved > 0)
          TextButton.icon(onPressed: () => sheet(context, VaultTransfer(from: g)), icon: const Icon(Icons.swap_horiz), label: const Text('Move to another vault')),
        const Section('Details'),
        Panel(
          child: Column(children: [
            _row('Actually saved', m(s.saved)),
            _row('Planned saving', planned ? '${m(g.contributionCents)} ${freqLabel(g.contributionFreq).toLowerCase()} (plan, not saved yet)' : 'None'),
            _row('Total deposits', m(s.deposits)),
            _row('Total withdrawals', '${m(s.withdrawals)}${s.emergencyWithdrawals > 0 ? ' (${m(s.emergencyWithdrawals)} emergency)' : ''}'),
            if (g.tripId != null) _row('Trip spending', m(s.goalSpending)),
            _row('Remaining', m(s.remaining)),
            _row('Target date', g.targetDate == null ? 'None' : '${prettyDate(g.targetDate!)} ${g.targetDate!.year}'),
            _row('Forecast', s.forecast == null ? 'Need deposits or a plan to forecast' : '${prettyDate(s.forecast!)} ${s.forecast!.year}'),
            _row('Savings Lock', g.locked ? 'On: withdrawals need extra confirmation' : 'Off'),
          ]),
        ),
        const Section('History'),
        if (history.isEmpty) const Empty('No deposits yet.'),
        for (final e in history) EventTile(e),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );
}

/// Deposit into / withdraw from a vault. Withdrawals ask why; locked vaults need a typed confirmation.
class MoveMoney extends StatefulWidget {
  final SavingsGoal goal;
  final bool deposit;
  const MoveMoney({super.key, required this.goal, required this.deposit});
  @override
  State<MoveMoney> createState() => _MoveMoneyState();
}

class _MoveMoneyState extends State<MoveMoney> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController(), lockText = TextEditingController();
  final String eventId = newId();
  String reason = 'planned';
  DateTime date = today();

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final app = context.appRead;
    final cents = parseCents(amount.text)!;
    final g = widget.goal;
    if (!widget.deposit) {
      final bal = app.data.ledger.goalBalance(g.id);
      if (cents > bal) return context.toast('Only ${m(bal)} is in this vault.');
      if (g.locked && lockText.text.trim().toUpperCase() != 'UNLOCK') {
        return context.toast('Type UNLOCK to withdraw from a locked vault.');
      }
    } else if (cents > app.data.availableToSpend && !await confirm(context, 'More than your free money',
        'This deposit is larger than your safe-to-spend amount (${m(app.data.availableToSpend)}). Save anyway?')) {
      return;
    }
    final e = app.event(
        id: eventId, kind: widget.deposit ? 'goal_deposit' : 'goal_withdraw', amountCents: cents, goalId: g.id, on: date,
        reason: widget.deposit ? null : reason, note: note.text);
    final shared = g.tripId != null && (app.data.trip(g.tripId)?.shared ?? false);
    app.record([e], trigger: GoalMoved(e), also: [
      if (shared)
        TripEntry(id: newId(), tripId: g.tripId!, kind: widget.deposit ? 'contribution' : 'withdrawal', amountCents: cents, occurredOn: date, ledgerEventId: e.id),
    ]);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${widget.deposit ? 'Deposit to' : 'Withdraw from'} ${widget.goal.name}', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.deposit
                ? 'Sets money aside inside your accounts. Your account balances don\'t change; your safe-to-spend does.'
                : 'Releases saved money back to spending money.', style: context.tt.bodySmall),
            const SizedBox(height: 12),
            AmountField(amount, autofocus: true),
            if (!widget.deposit) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final r in const {'planned': 'Planned use', 'emergency': 'Emergency', 'other': 'Other'}.entries)
                  ChoiceChip(label: Text(r.value), selected: reason == r.key, onSelected: (_) => setState(() => reason = r.key)),
              ]),
              if (reason == 'emergency')
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('Emergencies are what savings are for. Clover won\'t guilt you.', style: context.tt.bodySmall)),
              if (widget.goal.locked) ...[
                const SizedBox(height: 12),
                TextField(controller: lockText, decoration: const InputDecoration(labelText: 'Savings Lock: type UNLOCK', prefixIcon: Icon(Icons.lock_rounded))),
              ],
            ],
            const SizedBox(height: 12),
            DateField(value: date, onChanged: (d) => setState(() => date = d!)),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 16),
            FilledButton(onPressed: save, child: Text(widget.deposit ? 'Deposit' : 'Withdraw')),
          ]),
        ),
      );
}

class VaultTransfer extends StatefulWidget {
  final SavingsGoal from;
  const VaultTransfer({super.key, required this.from});
  @override
  State<VaultTransfer> createState() => _VaultTransferState();
}

class _VaultTransferState extends State<VaultTransfer> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController();
  String? to;

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Move between vaults', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          AmountField(amount, autofocus: true),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: to,
            decoration: const InputDecoration(labelText: 'To vault'),
            items: [for (final g in d.goals.where((g) => g.id != widget.from.id && !g.archived)) DropdownMenuItem(value: g.id, child: Text(g.name))],
            onChanged: (v) => setState(() => to = v),
            validator: (v) => v == null ? 'Pick a vault' : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final app = context.appRead;
              final cents = parseCents(amount.text)!;
              if (cents > app.data.ledger.goalBalance(widget.from.id)) return context.toast('Not enough in ${widget.from.name}.');
              if (widget.from.locked) return context.toast('${widget.from.name} is locked. Withdraw with UNLOCK first.');
              final grp = newId();
              app.record([
                app.event(kind: 'goal_withdraw', amountCents: cents, goalId: widget.from.id, reason: 'planned', groupId: grp, note: 'Vault transfer'),
                app.event(kind: 'goal_deposit', amountCents: cents, goalId: to, groupId: grp, note: 'Vault transfer'),
              ]);
              Navigator.pop(context);
            },
            child: const Text('Move'),
          ),
        ]),
      ),
    );
  }
}

class GoalEditor extends StatefulWidget {
  final SavingsGoal? existing;
  const GoalEditor({super.key, this.existing});
  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  final form = GlobalKey<FormState>();
  late final g = widget.existing ?? SavingsGoal(id: newId(), name: '', goalCents: 0);
  late final name = TextEditingController(text: g.name);
  late final goal = TextEditingController(text: g.goalCents == 0 ? '' : centsToInput(g.goalCents));
  late final contrib = TextEditingController(text: g.contributionCents == 0 ? '' : centsToInput(g.contributionCents));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existing == null ? 'New vault' : 'Edit vault', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Name it' : null),
            const SizedBox(height: 12),
            AmountField(goal, label: 'Goal amount'),
            const SizedBox(height: 12),
            DateField(value: g.targetDate, label: 'Target date (optional)', clearable: true, onChanged: (d) => setState(() => g.targetDate = d)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: contrib,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Planned contribution', prefixText: '\$ '),
                  validator: (v) => (v ?? '').isEmpty || (parseCents(v!) ?? -1) >= 0 ? null : 'Invalid',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: g.contributionFreq,
                  decoration: const InputDecoration(labelText: 'Schedule'),
                  items: [for (final f in const ['payday', 'weekly', 'monthly', 'none']) DropdownMenuItem(value: f, child: Text(freqLabel(f)))],
                  onChanged: (v) => setState(() => g.contributionFreq = v!),
                ),
              ),
            ]),
            SwitchListTile(
              value: g.locked,
              onChanged: (v) => setState(() => g.locked = v),
              title: const Text('Savings Lock'),
              subtitle: const Text('Withdrawals require typing UNLOCK. A habit tool, not a bank restriction.'),
            ),
            const Section('Color'),
            ColorChooser(value: g.color, onChanged: (v) => setState(() => g.color = v)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                g
                  ..name = name.text.trim()
                  ..goalCents = parseCents(goal.text)!
                  ..contributionCents = parseCents(contrib.text) ?? 0;
                context.appRead.save(g);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
            if (widget.existing != null)
              TextButton(
                onPressed: () {
                  g.archived = !g.archived;
                  context.appRead.save(g);
                  Navigator.pop(context);
                },
                child: Text(g.archived ? 'Unarchive' : 'Archive vault (history kept)'),
              ),
            if (widget.existing != null) DeleteButton(what: g.name, body: goalDeleteBody(context, g), toDelete: () => [g], pops: 2),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- trips
class TripCard extends StatelessWidget {
  final Trip t;
  const TripCard(this.t, {super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final s = tripSummary(d, t);
    final goal = d.goals.where((g) => g.tripId == t.id).firstOrNull;
    final saved = goal == null ? s.saved : d.ledger.goalBalance(goal.id);
    return Panel(
      color: Accents.vacation.withValues(alpha: 0.10),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetail(t.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flight_takeoff_rounded, color: Accents.vacationBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          if (t.shared) const Icon(Icons.group_rounded, size: 18, color: Accents.vacation),
          tripMenu(context, t),
        ]),
        if (t.destination != null || t.departOn != null)
          Text([if (t.destination != null) t.destination!, if (t.departOn != null) 'leaves ${prettyDate(t.departOn!)}'].join(' · '), style: context.tt.bodySmall),
        const SizedBox(height: 10),
        Bar(saved + s.paid, s.budget, color: Accents.vacation, height: 10),
        const SizedBox(height: 6),
        Text('${m(saved)} saved · ${m(s.paid)} paid · ${m(s.budget)} budget', style: context.tt.bodySmall),
      ]),
    );
  }
}

class TripDetail extends StatefulWidget {
  final String id;
  const TripDetail(this.id, {super.key});
  @override
  State<TripDetail> createState() => _TripDetailState();
}

class _TripDetailState extends State<TripDetail> {
  List<Map<String, dynamic>> members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final app = context.appRead;
    if (!app.signedIn) return;
    try {
      final rows = await app.client!.from('trip_members').select('user_id, role, status').eq('trip_id', widget.id);
      if (mounted) setState(() => members = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _invite() async {
    final app = context.appRead;
    if (!app.signedIn) return context.toast('Sign in with cloud sync to share trips.');
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Invite a friend'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Their STACKD email')),
          const SizedBox(height: 8),
          const Text('They will see this trip\'s plan, shared contributions and shared expenses. Never your accounts or other spending.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Invite')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.sync!.sync(); // trip must exist on the server first
      await app.client!.rpc('invite_to_trip', params: {'p_trip': widget.id, 'p_email': email.text.trim()});
      final t = app.data.trip(widget.id)!..shared = true;
      app.save(t);
      await _loadMembers();
      if (mounted) context.toast('Invite sent.');
    } catch (e) {
      if (mounted) context.toast('Invite failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = app.data;
    final t = d.trip(widget.id);
    if (t == null) return const Scaffold(body: Empty('Trip not found'));
    final s = tripSummary(d, t);
    final items = d.tripItems.where((i) => i.tripId == t.id).toList();
    final goal = d.goals.where((g) => g.tripId == t.id).firstOrNull;
    final saved = goal == null ? 0 : d.ledger.goalBalance(goal.id);
    final entries = d.tripEntries.where((e) => e.tripId == t.id).toList()..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    final mine = app.sync?.uid;
    final owner = t.ownerId == null || t.ownerId == mine;
    return Scaffold(
      appBar: AppBar(title: Text(t.name), actions: [
        if (owner) tripMenu(context, t, inDetail: true),
      ]),
      body: PageBody(children: [
        Panel(
          color: Accents.vacation.withValues(alpha: 0.12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (t.destination != null) Text(t.destination!, style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (t.departOn != null)
              Text('${prettyDate(t.departOn!)}${t.returnOn != null ? ' – ${prettyDate(t.returnOn!)}' : ''} · ${daysBetween(d.todayDate, t.departOn!)} days to go'),
            const SizedBox(height: 12),
            Wrap(spacing: 20, runSpacing: 10, children: [
              _kv('Budget', s.budget),
              _kv('Saved (your vault)', saved, Accents.savings),
              if (t.shared) _kv('Group contributions', s.saved, Accents.vacation),
              _kv('Already paid', s.paid),
              _kv('Remaining costs', s.remainingCost),
              _kv('Still to save', (s.remainingCost - (t.shared ? s.saved : saved)).clamp(0, 1 << 40), Accents.warn),
            ]),
            if (s.weeksLeft > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Projected need: ${m(ceilDiv((s.remainingCost - (t.shared ? s.saved : saved)).clamp(0, 1 << 40), s.weeksLeft))} per week until departure.'),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        if (goal != null)
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => sheet(context, MoveMoney(goal: goal, deposit: true)), icon: const Icon(Icons.savings), label: const Text('Add savings'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: saved <= 0 ? null : () => sheet(context, MoveMoney(goal: goal, deposit: false)), icon: const Icon(Icons.remove), label: const Text('Take out'))),
            IconButton(tooltip: 'Open vault', onPressed: () => _open(context, goal.id), icon: const Icon(Icons.open_in_new)),
          ])
        else
          OutlinedButton.icon(
            onPressed: () => app.save(SavingsGoal(id: newId(), name: t.name, goalCents: s.budget > 0 ? s.budget : 100000, tripId: t.id, targetDate: t.departOn, color: Accents.vacation.toARGB32())),
            icon: const Icon(Icons.add),
            label: const Text('Create a savings vault for this trip'),
          ),
        Section('Trip budget', trailing: IconButton(onPressed: () => sheet(context, TripItemEditor(tripId: t.id)), icon: const Icon(Icons.add))),
        if (items.isEmpty) const Panel(child: Text('Add flights, stay, food, activities... to plan the costs.')),
        for (final i in items)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(i.title),
              subtitle: Bar(s.paidByItem[i.id] ?? 0, i.plannedCents, color: Accents.vacationBlue),
              trailing: Text('${m(s.paidByItem[i.id] ?? 0)} / ${m(i.plannedCents)}'),
              onTap: () => sheet(context, TripItemEditor(tripId: t.id, existing: i)),
            ),
          ),
        Section('Shared expenses & contributions', trailing: IconButton(onPressed: () => sheet(context, TripExpense(trip: t, items: items)), icon: const Icon(Icons.add))),
        Text('Each expense is counted once: in the payer\'s own ledger and once in this shared view.', style: context.tt.bodySmall),
        for (final e in entries.take(100))
          ListTile(
            dense: true,
            leading: Icon(e.kind == 'expense' ? Icons.receipt_rounded : (e.kind == 'contribution' ? Icons.savings_rounded : Icons.outbox_rounded)),
            title: Text('${e.reversesId != null ? 'Reversal · ' : ''}${e.kind[0].toUpperCase()}${e.kind.substring(1)}${e.note != null ? ' · ${e.note}' : ''}'),
            subtitle: Text('${prettyDate(e.occurredOn)}${e.userId != null && e.userId != mine ? ' · friend' : ''}'),
            trailing: Money(e.amountCents, size: 14),
          ),
        if (app.signedIn) ...[
          Section('People', trailing: owner ? TextButton.icon(onPressed: _invite, icon: const Icon(Icons.person_add), label: const Text('Invite')) : null),
          for (final mbr in members)
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(mbr['user_id'] == mine ? 'You' : 'Member'),
              subtitle: Text('${mbr['role']} · ${mbr['status']}'),
            ),
        ],
      ]),
    );
  }

  Widget _kv(String k, int v, [Color? c]) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 11)),
        Money(v, size: 17, color: c),
      ]);
}

class TripEditor extends StatefulWidget {
  final Trip? existing;
  const TripEditor({super.key, this.existing});
  @override
  State<TripEditor> createState() => _TripEditorState();
}

class _TripEditorState extends State<TripEditor> {
  final form = GlobalKey<FormState>();
  late final t = widget.existing ?? Trip(id: newId(), name: '');
  late final name = TextEditingController(text: t.name), dest = TextEditingController(text: t.destination ?? '');
  late final budget = TextEditingController(text: t.budgetCents == 0 ? '' : centsToInput(t.budgetCents));
  bool makeVault = true;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existing == null ? 'New trip' : 'Edit trip', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Trip name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Name it' : null),
            const SizedBox(height: 12),
            TextFormField(controller: dest, decoration: const InputDecoration(labelText: 'Destination')),
            const SizedBox(height: 12),
            DateField(value: t.departOn, label: 'Departure', clearable: true, onChanged: (d) => setState(() => t.departOn = d)),
            const SizedBox(height: 12),
            DateField(value: t.returnOn, label: 'Return', clearable: true, onChanged: (d) => setState(() => t.returnOn = d)),
            const SizedBox(height: 12),
            TextFormField(
              controller: budget,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Overall budget (or leave blank to sum the items)', prefixText: '\$ '),
              validator: (v) => (v ?? '').isEmpty || (parseCents(v!) ?? -1) >= 0 ? null : 'Invalid',
            ),
            if (widget.existing == null)
              SwitchListTile(value: makeVault, onChanged: (v) => setState(() => makeVault = v), title: const Text('Create a savings vault for it')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                if (t.returnOn != null && t.departOn != null && t.returnOn!.isBefore(t.departOn!)) {
                  return context.toast('Return must be after departure.');
                }
                final app = context.appRead;
                t
                  ..name = name.text.trim()
                  ..destination = dest.text.trim().isEmpty ? null : dest.text.trim()
                  ..budgetCents = parseCents(budget.text) ?? 0;
                app.save(t);
                if (widget.existing == null && makeVault) {
                  app.save(SavingsGoal(id: newId(), name: t.name, goalCents: t.budgetCents > 0 ? t.budgetCents : 100000, tripId: t.id,
                      targetDate: t.departOn, color: Accents.vacation.toARGB32()));
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
            if (widget.existing != null)
              TextButton(
                onPressed: () {
                  t.archived = true;
                  context.appRead.save(t);
                  Navigator.pop(context);
                },
                child: const Text('Archive trip'),
              ),
            if (widget.existing != null) DeleteButton(what: t.name, body: _tripDeleteBody, toDelete: () => tripWithParts(context, t), pops: 2),
          ]),
        ),
      );
}

class TripItemEditor extends StatefulWidget {
  final String tripId;
  final TripBudgetItem? existing;
  const TripItemEditor({super.key, required this.tripId, this.existing});
  @override
  State<TripItemEditor> createState() => _TripItemEditorState();
}

class _TripItemEditorState extends State<TripItemEditor> {
  late final i = widget.existing ?? TripBudgetItem(id: newId(), tripId: widget.tripId, category: 'flights');
  late final label = TextEditingController(text: i.label ?? '');
  late final planned = TextEditingController(text: i.plannedCents == 0 ? '' : centsToInput(i.plannedCents));

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Budget item', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in TripBudgetItem.categories)
              ChoiceChip(label: Text(c[0].toUpperCase() + c.substring(1)), selected: i.category == c, onSelected: (_) => setState(() => i.category = c)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Label (optional)')),
          const SizedBox(height: 12),
          TextField(controller: planned, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Planned cost', prefixText: '\$ ')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              i
                ..label = label.text.trim().isEmpty ? null : label.text.trim()
                ..plannedCents = (parseCents(planned.text) ?? 0).abs();
              context.appRead.save(i);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
          if (widget.existing != null)
            TextButton(
              onPressed: () {
                i.deleted = true;
                context.appRead.save(i);
                Navigator.pop(context);
              },
              child: const Text('Remove item'),
            ),
        ]),
      );
}

/// Records a trip expense: one private ledger expense + one linked shared entry (no double counting).
class TripExpense extends StatefulWidget {
  final Trip trip;
  final List<TripBudgetItem> items;
  const TripExpense({super.key, required this.trip, required this.items});
  @override
  State<TripExpense> createState() => _TripExpenseState();
}

class _TripExpenseState extends State<TripExpense> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController();
  final String eventId = newId();
  String? account, item, category;
  DateTime date = today();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Trip expense', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            AmountField(amount, autofocus: true),
            const SizedBox(height: 12),
            if (widget.items.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: item,
                decoration: const InputDecoration(labelText: 'Trip budget item'),
                items: [const DropdownMenuItem(value: null, child: Text('General')), for (final i in widget.items) DropdownMenuItem(value: i.id, child: Text(i.title))],
                onChanged: (v) => setState(() => item = v),
              ),
              const SizedBox(height: 12),
            ],
            AccountPicker(value: account, onChanged: (v) => setState(() => account = v), label: 'Paid from'),
            const SizedBox(height: 12),
            CategoryPicker(value: category, required: false, onChanged: (v) => setState(() => category = v)),
            const SizedBox(height: 12),
            DateField(value: date, onChanged: (d) => setState(() => date = d!)),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'What was it?')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final app = context.appRead;
                final cents = parseCents(amount.text)!;
                final e = app.event(id: eventId, kind: 'expense', amountCents: cents, accountId: account, categoryId: category, tripId: widget.trip.id, on: date, note: note.text);
                app.record([e], trigger: ExpenseLogged(e), also: [
                  TripEntry(id: newId(), tripId: widget.trip.id, kind: 'expense', itemId: item, amountCents: cents, occurredOn: date, ledgerEventId: e.id,
                      note: note.text.trim().isEmpty ? null : note.text.trim()),
                ]);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ]),
        ),
      );
}
