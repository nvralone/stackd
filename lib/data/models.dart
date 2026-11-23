// Domain models. Each maps 1:1 to a Supabase table row (snake_case keys).
import '../core/dates.dart';

typedef DbRow = Map<String, Object?>;

String? _d(DateTime? d) => d == null ? null : isoDate(d);
DateTime? _pd(Object? v) => v == null ? null : parseDate(v as String);
int? _i(Object? v) => v == null ? null : (v as num).toInt();
bool _b(Object? v) => v == true || v == 1;

abstract class Entity {
  String get id;
  bool deleted = false;
  String get table;
  DbRow toRow();
}

class MoneyAccount extends Entity {
  @override
  final String id;
  String name, kind;
  int color, sort;
  bool archived;
  MoneyAccount({required this.id, required this.name, this.kind = 'cash', this.color = 0xFF7E57C2, this.sort = 0, this.archived = false});
  @override
  String get table => 'money_accounts';
  static const kinds = ['cash', 'venmo', 'cashapp', 'checking', 'savings', 'custom'];
  @override
  DbRow toRow() => {'id': id, 'name': name, 'kind': kind, 'color': color, 'sort': sort, 'archived': archived, 'deleted': deleted};
  factory MoneyAccount.fromRow(DbRow r) => MoneyAccount(
      id: r['id'] as String, name: r['name'] as String, kind: r['kind'] as String,
      color: _i(r['color'])!, sort: _i(r['sort']) ?? 0, archived: _b(r['archived']))
    ..deleted = _b(r['deleted']);
}

class Category extends Entity {
  @override
  final String id;
  String name, period;
  int color, icon, sort;
  int? limitCents;
  bool rollover, essential, archived;
  String? tag;
  Category({required this.id, required this.name, required this.color, this.icon = 0, this.limitCents,
      this.period = 'weekly', this.rollover = false, this.essential = false, this.tag, this.archived = false, this.sort = 0});
  @override
  String get table => 'categories';
  @override
  DbRow toRow() => {'id': id, 'name': name, 'color': color, 'icon': icon, 'limit_cents': limitCents, 'period': period,
        'rollover': rollover, 'essential': essential, 'tag': tag, 'archived': archived, 'sort': sort, 'deleted': deleted};
  factory Category.fromRow(DbRow r) => Category(
      id: r['id'] as String, name: r['name'] as String, color: _i(r['color'])!, icon: _i(r['icon']) ?? 0,
      limitCents: _i(r['limit_cents']), period: r['period'] as String? ?? 'weekly', rollover: _b(r['rollover']),
      essential: _b(r['essential']), tag: r['tag'] as String?, archived: _b(r['archived']), sort: _i(r['sort']) ?? 0)
    ..deleted = _b(r['deleted']);
}

class IncomeSchedule extends Entity {
  @override
  final String id;
  String name, frequency;
  DateTime anchorDate;
  int expectedCents;
  String? accountId;
  bool active;
  IncomeSchedule({required this.id, required this.name, required this.frequency, required this.anchorDate,
      this.expectedCents = 0, this.accountId, this.active = true});
  @override
  String get table => 'income_schedules';
  static const frequencies = ['weekly', 'biweekly', 'semimonthly', 'monthly', 'irregular'];
  @override
  DbRow toRow() => {'id': id, 'name': name, 'frequency': frequency, 'anchor_date': isoDate(anchorDate),
        'expected_cents': expectedCents, 'account_id': accountId, 'active': active, 'deleted': deleted};
  factory IncomeSchedule.fromRow(DbRow r) => IncomeSchedule(
      id: r['id'] as String, name: r['name'] as String, frequency: r['frequency'] as String,
      anchorDate: _pd(r['anchor_date'])!, expectedCents: _i(r['expected_cents']) ?? 0,
      accountId: r['account_id'] as String?, active: r['active'] == null || _b(r['active']))
    ..deleted = _b(r['deleted']);
}

class SavingsGoal extends Entity {
  @override
  final String id;
  String name, contributionFreq;
  int goalCents, contributionCents, color;
  DateTime? targetDate;
  bool locked, archived;
  String? tripId;
  SavingsGoal({required this.id, required this.name, required this.goalCents, this.targetDate, this.contributionCents = 0,
      this.contributionFreq = 'payday', this.locked = false, this.color = 0xFF66BB6A, this.tripId, this.archived = false});
  @override
  String get table => 'savings_goals';
  @override
  DbRow toRow() => {'id': id, 'name': name, 'goal_cents': goalCents, 'target_date': _d(targetDate),
        'contribution_cents': contributionCents, 'contribution_freq': contributionFreq, 'locked': locked,
        'color': color, 'trip_id': tripId, 'archived': archived, 'deleted': deleted};
  factory SavingsGoal.fromRow(DbRow r) => SavingsGoal(
      id: r['id'] as String, name: r['name'] as String, goalCents: _i(r['goal_cents'])!, targetDate: _pd(r['target_date']),
      contributionCents: _i(r['contribution_cents']) ?? 0, contributionFreq: r['contribution_freq'] as String? ?? 'payday',
      locked: _b(r['locked']), color: _i(r['color']) ?? 0xFF66BB6A, tripId: r['trip_id'] as String?, archived: _b(r['archived']))
    ..deleted = _b(r['deleted']);
}

class Bill extends Entity {
  @override
  final String id;
  String name, kind, frequency;
  int amountCents, feeCents, reminderDays;
  DateTime firstDue;
  int? paymentCount, principalCents;
  String? counterparty, categoryId, accountId;
  bool archived;
  Bill({required this.id, required this.name, this.kind = 'recurring', required this.amountCents, this.frequency = 'monthly',
      required this.firstDue, this.paymentCount, this.principalCents, this.feeCents = 0, this.counterparty,
      this.categoryId, this.accountId, this.reminderDays = 2, this.archived = false});
  @override
  String get table => 'bills';
  static const kinds = ['recurring', 'one_time', 'debt_owed', 'debt_lent'];
  static const frequencies = ['once', 'weekly', 'biweekly', 'monthly', 'yearly'];
  bool get isDebt => kind == 'debt_owed' || kind == 'debt_lent';
  /// Money flows in (friend repays you) instead of out.
  bool get incoming => kind == 'debt_lent';
  @override
  DbRow toRow() => {'id': id, 'name': name, 'kind': kind, 'amount_cents': amountCents, 'frequency': frequency,
        'first_due': isoDate(firstDue), 'payment_count': paymentCount, 'principal_cents': principalCents,
        'fee_cents': feeCents, 'counterparty': counterparty, 'category_id': categoryId, 'account_id': accountId,
        'reminder_days': reminderDays, 'archived': archived, 'deleted': deleted};
  factory Bill.fromRow(DbRow r) => Bill(
      id: r['id'] as String, name: r['name'] as String, kind: r['kind'] as String, amountCents: _i(r['amount_cents'])!,
      frequency: r['frequency'] as String, firstDue: _pd(r['first_due'])!, paymentCount: _i(r['payment_count']),
      principalCents: _i(r['principal_cents']), feeCents: _i(r['fee_cents']) ?? 0, counterparty: r['counterparty'] as String?,
      categoryId: r['category_id'] as String?, accountId: r['account_id'] as String?,
      reminderDays: _i(r['reminder_days']) ?? 2, archived: _b(r['archived']))
    ..deleted = _b(r['deleted']);
}

class BillOverride extends Entity {
  @override
  final String id;
  final String billId;
  final int occurrence;
  DateTime? dueOn;
  bool skipped, setAside;
  BillOverride({required this.id, required this.billId, required this.occurrence, this.dueOn, this.skipped = false, this.setAside = false});
  @override
  String get table => 'bill_overrides';
  @override
  DbRow toRow() => {'id': id, 'bill_id': billId, 'occurrence': occurrence, 'due_on': _d(dueOn), 'skipped': skipped, 'set_aside': setAside, 'deleted': deleted};
  factory BillOverride.fromRow(DbRow r) => BillOverride(
      id: r['id'] as String, billId: r['bill_id'] as String, occurrence: _i(r['occurrence'])!,
      dueOn: _pd(r['due_on']), skipped: _b(r['skipped']), setAside: _b(r['set_aside']))
    ..deleted = _b(r['deleted']);
}

class Trip extends Entity {
  @override
  final String id;
  String? ownerId, destination;
  String name;
  DateTime? departOn, returnOn;
  int budgetCents;
  bool shared, archived;
  Trip({required this.id, required this.name, this.ownerId, this.destination, this.departOn, this.returnOn,
      this.budgetCents = 0, this.shared = false, this.archived = false});
  @override
  String get table => 'trips';
  @override
  DbRow toRow() => {'id': id, if (ownerId != null) 'owner_id': ownerId, 'name': name, 'destination': destination,
        'depart_on': _d(departOn), 'return_on': _d(returnOn), 'budget_cents': budgetCents, 'shared': shared,
        'archived': archived, 'deleted': deleted};
  factory Trip.fromRow(DbRow r) => Trip(
      id: r['id'] as String, name: r['name'] as String, ownerId: r['owner_id'] as String?,
      destination: r['destination'] as String?, departOn: _pd(r['depart_on']), returnOn: _pd(r['return_on']),
      budgetCents: _i(r['budget_cents']) ?? 0, shared: _b(r['shared']), archived: _b(r['archived']))
    ..deleted = _b(r['deleted']);
}

class TripBudgetItem extends Entity {
  @override
  final String id;
  final String tripId;
  String category;
  String? label;
  int plannedCents;
  TripBudgetItem({required this.id, required this.tripId, required this.category, this.label, this.plannedCents = 0});
  @override
  String get table => 'trip_budget_items';
  static const categories = ['transportation', 'flights', 'accommodation', 'food', 'activities', 'shopping', 'emergency', 'custom'];
  String get title => label?.isNotEmpty == true ? label! : category[0].toUpperCase() + category.substring(1);
  @override
  DbRow toRow() => {'id': id, 'trip_id': tripId, 'category': category, 'label': label, 'planned_cents': plannedCents, 'deleted': deleted};
  factory TripBudgetItem.fromRow(DbRow r) => TripBudgetItem(
      id: r['id'] as String, tripId: r['trip_id'] as String, category: r['category'] as String,
      label: r['label'] as String?, plannedCents: _i(r['planned_cents']) ?? 0)
    ..deleted = _b(r['deleted']);
}

/// Extra budget added to a category for one period (e.g. from an Extra Money split). Not money movement.
class BudgetAllocation extends Entity {
  @override
  final String id;
  final String categoryId;
  final DateTime periodStart;
  final int amountCents;
  final String? groupId, note;
  BudgetAllocation({required this.id, required this.categoryId, required this.periodStart, required this.amountCents,
      this.groupId, this.note});
  @override
  String get table => 'budget_allocations';
  @override
  DbRow toRow() => {'id': id, 'category_id': categoryId, 'period_start': isoDate(periodStart), 'amount_cents': amountCents,
        'group_id': groupId, 'note': note, 'deleted': deleted};
  factory BudgetAllocation.fromRow(DbRow r) => BudgetAllocation(
      id: r['id'] as String, categoryId: r['category_id'] as String, periodStart: _pd(r['period_start'])!,
      amountCents: _i(r['amount_cents'])!, groupId: r['group_id'] as String?, note: r['note'] as String?)
    ..deleted = _b(r['deleted']);
}

/// Immutable shared trip row (contribution or expense).
class TripEntry extends Entity {
  @override
  final String id;
  final String tripId, kind;
  final String? userId, itemId, note, ledgerEventId, reversesId;
  final int amountCents;
  final DateTime occurredOn;
  TripEntry({required this.id, required this.tripId, required this.kind, required this.amountCents, required this.occurredOn,
      this.userId, this.itemId, this.note, this.ledgerEventId, this.reversesId});
  @override
  String get table => 'trip_entries';
  @override
  DbRow toRow() => {'id': id, 'trip_id': tripId, 'kind': kind, 'item_id': itemId, 'amount_cents': amountCents,
        'occurred_on': isoDate(occurredOn), 'note': note, 'ledger_event_id': ledgerEventId, 'reverses_id': reversesId,
        if (userId != null) 'user_id': userId};
  factory TripEntry.fromRow(DbRow r) => TripEntry(
      id: r['id'] as String, tripId: r['trip_id'] as String, kind: r['kind'] as String,
      amountCents: _i(r['amount_cents'])!, occurredOn: _pd(r['occurred_on'])!, userId: r['user_id'] as String?,
      itemId: r['item_id'] as String?, note: r['note'] as String?, ledgerEventId: r['ledger_event_id'] as String?,
      reversesId: r['reverses_id'] as String?);
}

/// Immutable financial event. Never updated; corrections are 'reversal' events plus a replacement.
class LedgerEvent extends Entity {
  static const kinds = ['opening', 'adjustment', 'income', 'refund', 'expense', 'transfer', 'goal_deposit',
    'goal_withdraw', 'bill_payment', 'loan_out', 'loan_in', 'reversal'];
  static const incomeSources = ['paycheck', 'side_job', 'tip', 'gift', 'sale', 'loan', 'other'];

  @override
  final String id;
  final String kind;
  final DateTime occurredOn;
  final int amountCents;
  final String? accountId, toAccountId, categoryId, goalId, billId, tripId, incomeSource, reason,
      groupId, reversesId, replacesId, note, deviceId;
  final int? billOccurrence;
  final DateTime? createdAt;

  LedgerEvent({required this.id, required this.kind, required this.occurredOn, required this.amountCents,
      this.accountId, this.toAccountId, this.categoryId, this.goalId, this.billId, this.billOccurrence, this.tripId,
      this.incomeSource, this.reason, this.groupId, this.reversesId, this.replacesId, this.note, this.deviceId, this.createdAt});

  @override
  String get table => 'ledger_events';

  /// Earned income excludes refunds and borrowed money.
  bool get isEarnedIncome => kind == 'income' && incomeSource != 'loan';

  @override
  DbRow toRow() => {'id': id, 'kind': kind, 'occurred_on': isoDate(occurredOn), 'amount_cents': amountCents,
        'account_id': accountId, 'to_account_id': toAccountId, 'category_id': categoryId, 'goal_id': goalId,
        'bill_id': billId, 'bill_occurrence': billOccurrence, 'trip_id': tripId, 'income_source': incomeSource,
        'reason': reason, 'group_id': groupId, 'reverses_id': reversesId, 'replaces_id': replacesId, 'note': note,
        'device_id': deviceId};

  factory LedgerEvent.fromRow(DbRow r) => LedgerEvent(
      id: r['id'] as String, kind: r['kind'] as String, occurredOn: _pd(r['occurred_on'])!,
      amountCents: _i(r['amount_cents'])!, accountId: r['account_id'] as String?, toAccountId: r['to_account_id'] as String?,
      categoryId: r['category_id'] as String?, goalId: r['goal_id'] as String?, billId: r['bill_id'] as String?,
      billOccurrence: _i(r['bill_occurrence']), tripId: r['trip_id'] as String?, incomeSource: r['income_source'] as String?,
      reason: r['reason'] as String?, groupId: r['group_id'] as String?, reversesId: r['reverses_id'] as String?,
      replacesId: r['replaces_id'] as String?, note: r['note'] as String?, deviceId: r['device_id'] as String?,
      createdAt: r['created_at'] == null ? null : DateTime.tryParse(r['created_at'] as String));
}

/// User preferences (profiles row).
class Prefs extends Entity {
  @override
  String id;
  String? displayName;
  String currency, theme;
  int weekStart;
  bool onboarded;
  Map<String, Object?> clover;
  Map<String, Object?> notifications;
  Prefs({this.id = 'local', this.displayName, this.currency = 'USD', this.theme = 'dark', this.weekStart = 1,
      this.onboarded = false, Map<String, Object?>? clover, Map<String, Object?>? notifications})
      : clover = clover ?? {},
        notifications = notifications ?? {};
  @override
  String get table => 'profiles';

  String get personality => clover['personality'] as String? ?? 'chaotic';
  int get voiceVolume => _i(clover['volume']) ?? 70;
  bool get voiceMuted => clover['muted'] == true;
  bool get silent => clover['silent'] == true;
  bool get subtitles => clover['subtitles'] != false;
  bool get useTts => clover['tts'] != false;
  /// 'talk' = says the words in a goofy pitched voice; 'babble' = cartoon gibberish.
  String get voiceStyle => clover['voice'] as String? ?? 'talk'; // talk | clover | babble
  /// Character voice (offline Kokoro): pitch raise.
  double get voicePitch => (clover['voice_pitch'] as num?)?.toDouble() ?? 1.18;
  String get frequency => clover['frequency'] as String? ?? 'normal'; // low | normal | high
  /// Chaotic and Savage Clover may swear (never Friendly). Off = clean lines only.
  bool get swearing => clover['swear'] != false;
  bool notif(String key) => notifications[key] != false;
  int get quietStart => _i(notifications['quiet_start']) ?? 22;
  int get quietEnd => _i(notifications['quiet_end']) ?? 8;

  @override
  DbRow toRow() => {'id': id, 'user_id': id, 'display_name': displayName, 'currency': currency, 'theme': theme,
        'week_start': weekStart, 'onboarded': onboarded, 'clover': clover, 'notifications': notifications, 'deleted': deleted};
  factory Prefs.fromRow(DbRow r) => Prefs(
      id: r['id'] as String, displayName: r['display_name'] as String?, currency: r['currency'] as String? ?? 'USD',
      theme: r['theme'] as String? ?? 'dark', weekStart: _i(r['week_start']) ?? 1, onboarded: _b(r['onboarded']),
      clover: Map<String, Object?>.from(r['clover'] as Map? ?? {}),
      notifications: Map<String, Object?>.from(r['notifications'] as Map? ?? {}));
}
