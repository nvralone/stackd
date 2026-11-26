// 10-step setup. Optional steps can be skipped. Nothing here invents transactions.
import 'package:material_ui/material_ui.dart';

import '../../clover/brain.dart';
import '../../clover/clover_widget.dart';
import '../../clover/moods.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';
import 'bills.dart';
import 'goals.dart';
import 'settings.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  final name = TextEditingController();
  String freq = 'weekly';
  DateTime payday = today();
  final income = TextEditingController();
  final limits = <String, TextEditingController>{};

  static const titles = [
    'Welcome to STAKD',
    'Your money accounts',
    'How often do you get paid?',
    'About how much per paycheck?',
    'Recurring bills',
    'Spending categories',
    'Weekly & monthly budgets',
    'A savings goal',
    'A vacation (optional)',
    'Meet Clover',
  ];
  static const moods = [
    CloverMood.happy, CloverMood.thinking, CloverMood.dollarEyes, CloverMood.smug, CloverMood.suspicious,
    CloverMood.determined, CloverMood.proud, CloverMood.excited, CloverMood.vacation, CloverMood.celebrating,
  ];
  static const optional = {4, 7, 8};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.appRead.ensureDefaults());
  }

  void next() {
    final app = context.appRead;
    switch (step) {
      case 0:
        if (name.text.trim().isNotEmpty) app.savePrefs((p) => p.displayName = name.text.trim());
      case 3:
        final existing = app.data.schedules.firstOrNull;
        app.save((existing ?? IncomeSchedule(id: newId(), name: 'Paycheck', frequency: freq, anchorDate: payday))
          ..frequency = freq
          ..anchorDate = payday
          ..expectedCents = (parseCents(income.text) ?? 0).abs());
      case 6:
        for (final e in limits.entries) {
          final c = app.data.category(e.key);
          if (c == null) continue;
          final v = e.value.text.trim().isEmpty ? null : parseCents(e.value.text)?.abs();
          if (v != c.limitCents) app.save(c..limitCents = v);
        }
      case 9:
        app.savePrefs((p) => p.onboarded = true);
        app.refreshHomeClover();
        return;
    }
    setState(() => step++);
  }

  @override
  Widget build(BuildContext context) {
    context.app; // rebuild on data changes
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  if (step > 0) IconButton(onPressed: () => setState(() => step--), icon: const Icon(Icons.arrow_back)),
                  Expanded(child: LinearProgressIndicator(value: (step + 1) / titles.length, borderRadius: BorderRadius.circular(8))),
                  const SizedBox(width: 12),
                  Text('${step + 1}/${titles.length}'),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Center(child: CloverSprite(mood: moods[step], size: 100)),
                  const SizedBox(height: 8),
                  Text(titles[step], textAlign: TextAlign.center, style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  ..._body(context),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  if (optional.contains(step)) TextButton(onPressed: () => setState(() => step++), child: const Text('Skip')),
                  const Spacer(),
                  FilledButton(onPressed: next, child: Text(step == 9 ? "Let's go" : 'Next')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final app = context.app;
    final data = app.data;
    switch (step) {
      case 0:
        return [
          Text(app.signedIn ? 'Signed in. Your data syncs privately to your account.' : 'Running on this device only. You can sign in later from Settings.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'What should Clover call you? (optional)')),
          const SizedBox(height: 12),
          const Text('STAKD never connects to your bank. You record money yourself, and every change is reversible and audited.', textAlign: TextAlign.center),
        ];
      case 1:
        return [
          const Text('Add where your money lives and how much is there right now. Cash, Venmo, Cash App, checking, savings...', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          for (final a in data.accounts)
            ListTile(leading: Icon(accountIcon(a.kind), color: Color(a.color)), title: Text(a.name), trailing: Money(data.accountSpendable(a.id))),
          OutlinedButton.icon(onPressed: () => sheet(context, const AccountEditor()), icon: const Icon(Icons.add), label: const Text('Add account')),
          if (data.accounts.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('You can also add accounts later.', textAlign: TextAlign.center)),
        ];
      case 2:
        return [
          RadioGroup<String>(
            groupValue: freq,
            onChanged: (v) => setState(() => freq = v!),
            child: Column(children: [
              for (final f in const ['weekly', 'biweekly', 'semimonthly', 'monthly', 'irregular']) RadioListTile<String>(value: f, title: Text(freqLabel(f))),
            ]),
          ),
          if (freq != 'irregular') DateField(value: payday, label: 'Your next (or most recent) payday', onChanged: (v) => setState(() => payday = v!)),
        ];
      case 3:
        return [
          const Text('An estimate is fine. It\'s only used for forecasts; you log the real amount each payday.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextField(controller: income, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Typical paycheck', prefixText: '\$ ')),
        ];
      case 4:
        return [
          const Text('Rent, insurance, subscriptions, loans... Set the next due date and STAKD reserves money for it.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          for (final b in data.bills) ListTile(title: Text(b.name), subtitle: Text('${m(b.amountCents)} · ${freqLabel(b.frequency)}')),
          OutlinedButton.icon(onPressed: () => sheet(context, const BillEditor()), icon: const Icon(Icons.add), label: const Text('Add bill or debt')),
        ];
      case 5:
        return [
          const Text('Turn off the ones you don\'t need. You can add, rename and recolor anytime.', textAlign: TextAlign.center),
          for (final c in data.categories)
            SwitchListTile(
              secondary: CatDot(c),
              title: Text(c.name),
              value: !c.archived,
              onChanged: (v) => app.save(c..archived = !v),
            ),
        ];
      case 6:
        return [
          const Text('Optional limits. Leave blank for no limit. Weekly unless you change it later.', textAlign: TextAlign.center),
          for (final c in data.categories.where((c) => !c.archived))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                CatDot(c),
                const SizedBox(width: 10),
                Expanded(child: Text(c.name)),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: limits.putIfAbsent(c.id, () => TextEditingController(text: c.limitCents == null ? '' : centsToInput(c.limitCents!))),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(prefixText: '\$ ', isDense: true, suffixText: c.period == 'monthly' ? '/mo' : '/wk'),
                  ),
                ),
              ]),
            ),
        ];
      case 7:
        return [
          const Text('Emergency fund, new phone, car... Saved money stays in your accounts but is set aside from spending.', textAlign: TextAlign.center),
          for (final g in data.goals.where((g) => g.tripId == null)) ListTile(leading: const Icon(Icons.savings, color: Accents.savings), title: Text(g.name), trailing: Text(m(g.goalCents))),
          OutlinedButton.icon(onPressed: () => sheet(context, const GoalEditor()), icon: const Icon(Icons.add), label: const Text('Add a vault')),
        ];
      case 8:
        return [
          const Text('Dreaming of a trip? Plan it and Clover will help you fund it. Friends can join shared trips.', textAlign: TextAlign.center),
          for (final t in data.trips) ListTile(leading: const Icon(Icons.flight, color: Accents.vacation), title: Text(t.name)),
          OutlinedButton.icon(onPressed: () => sheet(context, const TripEditor()), icon: const Icon(Icons.add), label: const Text('Plan a vacation')),
        ];
      default:
        return [
          CloverCard(
            says: CloverSays('intro', 'intro', CloverMood.happy, switch (app.prefs.personality) {
              'friendly' => "Hi! I'm Clover. I'll cheer you on and keep an eye on your bills.",
              'savage' => "I'm Clover. I will roast your drive-thru habit. With love. Mostly.",
              _ => "I'M CLOVER! I'm a raccoon and I'm VERY into your money. Let's stack it!",
            }),
            onReplay: () => app.speak(app.cloverNow ?? const CloverSays('i', 'i', CloverMood.happy, 'Hi!'), force: true),
          ),
          const SizedBox(height: 16),
          const CloverSettings(),
        ];
    }
  }
}
