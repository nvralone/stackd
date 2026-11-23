// Single source of truth for the UI. All writes go through here -> LocalDb -> sync queue.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../clover/brain.dart';
import '../clover/kokoro_voice.dart';
import '../clover/voice.dart';
import '../core/dates.dart';
import '../core/ids.dart';
import '../core/money.dart';
import '../data/defaults.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import '../data/sync.dart';
import '../domain/allocation.dart';
import '../domain/finance.dart';
import '../services/notifications.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
bool get cloudConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

class AppState extends ChangeNotifier {
  final LocalDb db;
  final SyncService? sync;
  final Notifier? notifier;
  final CloverVoice? voice;
  late final String deviceId;
  late FinanceData data;
  late CloverBrain brain;
  CloverSays? cloverNow;
  /// True while Clover's voice is playing (drives the talking mouth animation).
  final talking = ValueNotifier<bool>(false);
  bool localOnlyChosen;
  Timer? _syncDebounce, _notifyDebounce;
  final DateTime Function() clock;

  AppState(this.db, {this.sync, this.notifier, this.voice, DateTime Function()? clock})
      : clock = clock ?? DateTime.now,
        localOnlyChosen = false {
    deviceId = db.getKv('device_id') ?? newId();
    db.setKv('device_id', deviceId);
    localOnlyChosen = db.getKv('local_only') == '1';
    brain = CloverBrain(_loadHistory());
    voice?.onTalking = (v) => talking.value = v;
    // If the saved login is restored or refreshed after startup, leave the sign-in screen automatically.
    sync?.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null && !localOnlyChosen) {
        if (sync?.state != SyncState.syncing) sync?.start();
        reload();
        notifyListeners();
      }
    }, onError: (_) {});
    reload();
  }

  static Future<AppState> boot() async {
    final dir = await getApplicationSupportDirectory();
    final db = LocalDb.open('${dir.path}${Platform.pathSeparator}stackd.db');
    SyncService? sync;
    late AppState app;
    if (cloudConfigured) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
      sync = SyncService(db, Supabase.instance.client, () => app._afterSync());
    }
    final notifier = Notifier();
    await notifier.init();
    app = AppState(db, sync: sync, notifier: notifier, voice: CloverVoice());
    if (sync != null && sync.uid != null) sync.start();
    app._scheduleNotifications();
    app._prepareVoice();
    return app;
  }

  // ---------------------------------------------------------------- loading
  List<T> _load<T>(String t, T Function(DbRow) f) => db.all(t).map(f).toList();

  Prefs get prefs => data.prefs;
  bool get signedIn => sync?.uid != null;
  bool get needsAuth => cloudConfigured && !signedIn && !localOnlyChosen;
  /// Signed in on this device but the first download hasn't finished: don't start setup yet.
  bool get firstSyncPending => signedIn && db.getKv('first_sync_done') == null && sync?.state != SyncState.error;
  int get pendingSync => db.dirtyCount;

  void reload() {
    final profiles = _load('profiles', Prefs.fromRow);
    final uid = sync?.uid;
    final prefs = profiles.where((p) => p.id == uid).firstOrNull ?? profiles.firstOrNull ?? Prefs();
    data = FinanceData(
      accounts: _load('money_accounts', MoneyAccount.fromRow)..sort((a, b) => a.sort.compareTo(b.sort)),
      categories: _load('categories', Category.fromRow)..sort((a, b) => a.sort.compareTo(b.sort)),
      goals: _load('savings_goals', SavingsGoal.fromRow),
      bills: _load('bills', Bill.fromRow),
      overrides: _load('bill_overrides', BillOverride.fromRow),
      schedules: _load('income_schedules', IncomeSchedule.fromRow),
      budgetAllocations: _load('budget_allocations', BudgetAllocation.fromRow),
      trips: _load('trips', Trip.fromRow),
      tripItems: _load('trip_budget_items', TripBudgetItem.fromRow),
      tripEntries: _load('trip_entries', TripEntry.fromRow),
      events: _load('ledger_events', LedgerEvent.fromRow),
      prefs: prefs,
      now: clock(),
    );
    cloverNow ??= brain.home(data);
  }

  void _changed({bool refreshClover = false}) {
    reload();
    if (refreshClover) refreshHomeClover();
    notifyListeners();
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 2), () => sync?.sync());
    _scheduleNotifications();
  }

  void _afterSync() {
    reload();
    cloverNow = brain.home(data); // keep Clover's message in step with freshly synced numbers
    _prepareVoice();
    notifyListeners();
  }

  /// Character voice: make the current Home line ahead of time so replay plays instantly.
  void _prepareVoice() {
    final s = cloverNow;
    final p = prefs;
    if (s == null || p.voiceStyle != 'clover' || p.silent) return;
    voice?.prepare(s.text, s.mood, VoiceStyle(sid: cloverSid, pitch: p.voicePitch));
  }

  void _scheduleNotifications() {
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(seconds: 3), () => notifier?.reschedule(planReminders(data)));
  }

  // ---------------------------------------------------------------- generic writes
  void save(Entity e) {
    db.put(e);
    _changed();
  }

  /// Soft delete (synced). Ledger history that referenced these items is kept.
  void deleteItems(List<Entity> items) {
    db.transaction(() {
      for (final e in items) {
        e.deleted = true;
        db.put(e);
      }
    });
    _changed(refreshClover: true);
  }

  void savePrefs(void Function(Prefs p) edit) {
    final p = prefs;
    edit(p);
    db.put(p);
    _changed();
  }

  /// Records events atomically. Duplicate ids (double taps, retries) are ignored.
  void record(List<LedgerEvent> events, {CloverTrigger? trigger, List<Entity> also = const []}) {
    db.transaction(() {
      for (final e in events) {
        db.put(e);
      }
      for (final e in also) {
        db.put(e);
      }
    });
    reload();
    if (trigger != null) _react(trigger);
    _limitWarnings(events);
    _changed();
  }

  LedgerEvent event({
    String? id,
    required String kind,
    required int amountCents,
    DateTime? on,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? goalId,
    String? billId,
    int? billOccurrence,
    String? tripId,
    String? incomeSource,
    String? reason,
    String? groupId,
    String? replacesId,
    String? note,
  }) =>
      LedgerEvent(
          id: id ?? newId(), kind: kind, occurredOn: on ?? today(clock()), amountCents: amountCents,
          accountId: accountId, toAccountId: toAccountId, categoryId: categoryId, goalId: goalId, billId: billId,
          billOccurrence: billOccurrence, tripId: tripId, incomeSource: incomeSource, reason: reason, groupId: groupId,
          replacesId: replacesId, note: (note?.trim().isEmpty ?? true) ? null : note!.trim(), deviceId: deviceId);

  /// Safe delete: appends a reversal. The original stays in the audit trail.
  void reverse(LedgerEvent e, {String? note}) {
    if (data.ledger.isReversed(e.id) || e.kind == 'reversal') return;
    final linked = data.tripEntries.where((t) => t.ledgerEventId == e.id).toList();
    record([
      event(kind: 'reversal', amountCents: e.amountCents.abs(), on: e.occurredOn, note: note ?? 'Reversed')
          .copyWithReverses(e.id)
    ], also: [
      for (final t in linked)
        TripEntry(id: newId(), tripId: t.tripId, kind: t.kind, amountCents: t.amountCents, occurredOn: t.occurredOn,
            itemId: t.itemId, reversesId: t.id, note: 'Reversed')
    ]);
  }

  /// Edit = reverse the original + record the corrected replacement, in one transaction.
  void edit(LedgerEvent original, LedgerEvent replacement) {
    final rev = event(kind: 'reversal', amountCents: original.amountCents.abs(), on: original.occurredOn, note: 'Edited')
        .copyWithReverses(original.id);
    record([rev, replacement]);
  }

  /// Reverses every event created together (e.g. an income + its allocation split).
  void reverseGroup(String groupId) {
    for (final e in data.ledger.active.where((e) => e.groupId == groupId).toList()) {
      reverse(e, note: 'Group undone');
    }
    for (final a in data.budgetAllocations.where((a) => a.groupId == groupId)) {
      a.deleted = true;
      db.put(a);
    }
    _changed();
  }

  LedgerEvent _reversalOf(LedgerEvent e, String note) =>
      event(kind: 'reversal', amountCents: e.amountCents.abs(), on: e.occurredOn, note: note).copyWithReverses(e.id);

  /// Changes where a split's money went: reverses the group's vault deposits, removes its budget
  /// boosts, and records the new ones, all in one step. The income itself is untouched.
  void replaceSplit(String groupId, List<LedgerEvent> deposits, List<BudgetAllocation> allocs) {
    final oldDeposits = data.ledger.active.where((e) => e.groupId == groupId && e.kind == 'goal_deposit').toList();
    // budget reductions from a paycheck split (negative) stay; only boosts are replaced
    final oldAllocs = data.budgetAllocations.where((a) => a.groupId == groupId && a.amountCents > 0).toList();
    record([for (final e in oldDeposits) _reversalOf(e, 'Split edited'), ...deposits],
        also: [for (final a in oldAllocs) a..deleted = true, ...allocs]);
  }

  /// Brings back a reversed entry as a fresh copy (the reversal stays in history).
  void restore(LedgerEvent reversed) {
    if (!data.ledger.isReversed(reversed.id)) return;
    record([reversed.replacement(newId: newId(), note: reversed.note)]);
  }

  /// Clears all money activity (as reversals, so history stays) but keeps accounts, bills, goals and
  /// budgets. With [keepSavings], money already put in vaults stays saved.
  void startFresh({bool keepSavings = true}) {
    final undo = data.ledger.active
        .where((e) => !(keepSavings && (e.kind == 'goal_deposit' || e.kind == 'goal_withdraw')))
        .toList();
    record([for (final e in undo) _reversalOf(e, 'Fresh start')], also: [
      for (final a in data.budgetAllocations) a..deleted = true,
      for (final o in data.overrides.where((o) => o.setAside)) o..setAside = false,
    ]);
  }

  /// The Bill savings envelope (created the first time it's needed).
  SavingsGoal billEnvelope() {
    final existing = data.goals.where((g) => g.name == billSavingsName && !g.archived).firstOrNull;
    if (existing != null) return existing;
    final g = SavingsGoal(id: newId(), name: billSavingsName, goalCents: 50000, contributionFreq: 'none', color: 0xFFFFA94D);
    save(g);
    return g;
  }

  /// Put money in the Bill savings envelope. [newCash]: money the app doesn't know about yet (total goes up,
  /// spare unchanged). Otherwise it comes out of spare money.
  /// The money is set aside for the later bills it was recommended for (soonest first); anything
  /// beyond that stays unassigned in the envelope.
  void addToBillEnvelope(int cents, {bool newCash = false, String? accountId}) {
    final split = envelopeSplit(data, cents);
    final g = billEnvelope();
    final acct = accountId ?? data.accounts.where((a) => !a.archived).firstOrNull?.id;
    final grp = newId();
    record([
      if (newCash && acct != null) event(kind: 'adjustment', amountCents: cents, accountId: acct, groupId: grp, note: 'Cash for bills'),
      for (final e in split.entries)
        event(kind: 'goal_deposit', amountCents: e.value, goalId: g.id, billId: e.key, groupId: grp,
            note: e.key == null ? 'Bill savings' : 'For ${data.bill(e.key)?.name ?? 'a bill'}'),
    ]);
    final dep = data.ledger.active.where((e) => e.groupId == grp && e.kind == 'goal_deposit').firstOrNull;
    if (dep != null) {
      _react(GoalMoved(dep));
      notifyListeners();
    }
  }

  /// Take money back out of the Bill savings envelope into spare money.
  void takeFromBillEnvelope(int cents) {
    final g = billEnvelope();
    final w = event(kind: 'goal_withdraw', amountCents: cents, goalId: g.id, reason: 'planned', note: 'Back to spare money');
    record([w], trigger: GoalMoved(w));
  }

  /// Removes one category boost (extra budget) without touching anything else.
  void removeBoost(BudgetAllocation a) => deleteItems([a]);

  // ---------------------------------------------------------------- setup helpers
  void skipFirstSync() {
    db.setKv('first_sync_done', '1');
    notifyListeners();
  }

  void ensureDefaults() {
    if (firstSyncPending) return; // wait: the account may already have categories
    if (db.all('categories').isEmpty) {
      db.transaction(() {
        for (final c in defaultCategories()) {
          db.put(c);
        }
      });
      _changed();
    }
  }

  /// New manual account with an auditable opening-balance event.
  void createAccount(MoneyAccount a, int openingCents) {
    record([if (openingCents != 0) event(kind: 'opening', amountCents: openingCents, accountId: a.id, note: 'Starting balance')],
        also: [a]);
  }

  // ---------------------------------------------------------------- Clover
  List<String> _loadHistory() {
    final raw = db.getKv('clover_history');
    return raw == null ? <String>[] : List<String>.from(jsonDecode(raw) as List);
  }

  void _remember(CloverSays s) {
    brain.history.add(s.lineId);
    if (brain.history.length > 80) brain.history.removeRange(0, brain.history.length - 80);
    db.setKv('clover_history', jsonEncode(brain.history));
  }

  void refreshHomeClover() {
    final s = brain.home(data);
    _remember(s);
    cloverNow = s;
    _prepareVoice();
    notifyListeners();
  }

  void _react(CloverTrigger t) {
    final s = brain.react(data, t);
    if (s == null) return;
    _remember(s);
    cloverNow = s;
    speak(s);
  }

  void speak(CloverSays s, {bool narrate = false, bool force = false}) {
    final p = prefs;
    if (p.silent || (p.voiceMuted && !force)) return;
    if (p.voiceStyle == 'babble' && !narrate) {
      voice?.babble(s.text, s.mood, volume: p.voiceVolume);
    } else if (p.voiceStyle == 'clover') {
      voice?.character(s.text, s.mood, volume: p.voiceVolume, style: VoiceStyle(sid: cloverSid, pitch: p.voicePitch));
    } else {
      voice?.talk(s.text, s.mood, volume: p.voiceVolume, chirp: !narrate);
    }
  }

  void _limitWarnings(List<LedgerEvent> events) {
    for (final e in events.where((e) => e.kind == 'expense' && e.categoryId != null)) {
      final c = data.category(e.categoryId);
      if (c == null || c.limitCents == null || !prefs.notif('limits')) continue;
      final st = data.categoryStatus(c);
      final before = st.spent - e.amountCents;
      if (st.budget > 0 && before * 100 < st.budget * 80 && st.spent * 100 >= st.budget * 80) {
        notifier?.now('${c.name} budget', '${st.pct}% used (${formatCents(st.spent)} of ${formatCents(st.budget)}).',
            quietStart: prefs.quietStart, quietEnd: prefs.quietEnd);
      }
    }
    for (final e in events.where((e) => e.kind == 'goal_deposit')) {
      final g = data.goal(e.goalId);
      if (g == null || g.tripId == null || !prefs.notif('vacation')) continue;
      final now = data.goalStatus(g).pct;
      final before = percentOf(data.ledger.goalBalance(g.id) - e.amountCents, g.goalCents);
      for (final m in [25, 50, 75, 100]) {
        if (before < m && now >= m) {
          notifier?.now('${g.name}: $m%!', 'Vacation savings milestone reached.', quietStart: prefs.quietStart, quietEnd: prefs.quietEnd);
        }
      }
    }
  }

  // ---------------------------------------------------------------- auth & account
  SupabaseClient? get client => sync?.client;

  String? get accountEmail => client?.auth.currentUser?.email;

  /// Usernames: 3-20 of a-z 0-9 _ . (case doesn't matter).
  static String? usernameProblem(String u) =>
      RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(u.trim().toLowerCase()) ? null : '3-20 letters, numbers, _ or .';

  /// Sign in with an email OR a username, same password either way. Username sign-in goes through the
  /// server function so nobody's email is ever sent to a device.
  Future<void> signIn(String login, String password) async {
    final id = login.trim();
    if (id.contains('@')) {
      await client!.auth.signInWithPassword(email: id, password: password);
    } else {
      String? refresh;
      try {
        final r = await client!.functions.invoke('username-login', body: {'username': id.toLowerCase(), 'password': password});
        refresh = (r.data as Map?)?['refresh_token'] as String?;
      } catch (_) {
        refresh = null;
      }
      if (refresh == null) throw Exception('Wrong username or password.');
      await client!.auth.setSession(refresh);
    }
    _adoptLocalProfile();
    sync!.start();
    _changed();
  }

  Future<String> signUp(String username, String email, String password) async {
    final u = username.trim().toLowerCase();
    final problem = usernameProblem(u);
    if (problem != null) throw Exception('Username: $problem');
    if (await client!.rpc('username_available', params: {'u': u}) != true) throw Exception('That username is taken.');
    final r = await client!.auth.signUp(email: email.trim(), password: password);
    if (r.session == null) return 'Account created. Sign in to continue.';
    _adoptLocalProfile();
    await setUsername(u);
    sync!.start();
    _changed();
    return 'Account created.';
  }

  /// Claims (or changes) this account's username on the server, then remembers it locally.
  Future<void> setUsername(String username) async {
    final u = username.trim().toLowerCase();
    final problem = usernameProblem(u);
    if (problem != null) throw Exception(problem);
    try {
      await client!.rpc('claim_username', params: {'u': u});
    } on PostgrestException catch (e) {
      throw Exception(e.message.contains('taken') ? 'That username is taken.' : e.message);
    }
    final uid = sync?.uid;
    final existing = db.all('profiles').where((r) => r['id'] == uid).firstOrNull;
    final p = existing != null ? Prefs.fromRow(existing) : (prefs..id = uid ?? prefs.id);
    db.put(p..username = u);
    _changed();
  }

  void _adoptLocalProfile() {
    final uid = sync?.uid;
    if (uid == null) return;
    final local = db.all('profiles').where((r) => r['id'] == 'local').firstOrNull;
    if (local != null) {
      db.db.execute("delete from rows where tbl = 'profiles' and id = 'local'");
      // A device that was already set up keeps its settings (fresh timestamp wins the merge).
      // A brand-new device drops its blank profile and takes the account's synced one.
      if (Prefs.fromRow(local).onboarded) db.put(Prefs.fromRow(local)..id = uid);
    }
  }

  void useLocalOnly() {
    db.setKv('local_only', '1');
    localOnlyChosen = true;
    notifyListeners();
  }

  /// Signs out and wipes local financial data so the next user of this device sees nothing.
  Future<void> signOut() async {
    sync?.stop();
    await client?.auth.signOut();
    db.wipe();
    localOnlyChosen = false;
    cloverNow = null;
    brain.history.clear();
    reload();
    notifyListeners();
    await notifier?.reschedule(const []);
  }

  Future<void> deleteAccount() async {
    if (signedIn) await client!.rpc('delete_my_account');
    await signOut();
    db.wipe();
    reload();
    notifyListeners();
  }

  Future<String> exportJson() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}stackd-export-${isoDate(today(clock()))}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(db.export()));
    return f.path;
  }
}

extension ReversalX on LedgerEvent {
  LedgerEvent copyWithReverses(String id) => LedgerEvent(
      id: this.id, kind: kind, occurredOn: occurredOn, amountCents: amountCents, reversesId: id, note: note, deviceId: deviceId);

  /// Same event data with a fresh id, used to build an edited replacement.
  LedgerEvent replacement({
    required String newId,
    int? amountCents,
    DateTime? on,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? note,
  }) =>
      LedgerEvent(
          id: newId, kind: kind, occurredOn: on ?? occurredOn, amountCents: amountCents ?? this.amountCents,
          accountId: accountId ?? this.accountId, toAccountId: toAccountId ?? this.toAccountId,
          categoryId: categoryId ?? this.categoryId, goalId: goalId, billId: billId, billOccurrence: billOccurrence,
          tripId: tripId, incomeSource: incomeSource, reason: reason, groupId: groupId, replacesId: id,
          note: note ?? this.note, deviceId: deviceId);
}
