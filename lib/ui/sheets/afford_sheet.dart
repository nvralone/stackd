// "Can I afford it?" — instant check of an extra purchase against safe-to-spend and the category budget.
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../common.dart';
import '../theme.dart';
import 'entry_sheet.dart';

class AffordSheet extends StatefulWidget {
  const AffordSheet({super.key});
  @override
  State<AffordSheet> createState() => _AffordSheetState();
}

class _AffordSheetState extends State<AffordSheet> {
  final amount = TextEditingController(), what = TextEditingController();
  String? category;

  @override
  Widget build(BuildContext context) {
    final d = context.app.data;
    final cents = (parseCents(amount.text) ?? 0).abs();
    final free = d.availableToSpend;
    final after = free - cents;
    final days = d.daysUntilHorizon;
    final dailyAfter = after <= 0 ? 0 : after ~/ days;
    final cat = d.category(category);
    final st = cat == null ? null : d.categoryStatus(cat);
    final catLeftAfter = st == null || !st.hasLimit ? null : st.remaining - cents;

    final (verdict, color, icon) = cents == 0
        ? ('Type a price to check it.', context.cs.onSurfaceVariant, Icons.help_outline_rounded)
        : after < 0
            ? ('Not right now: that dips ${m(-after)} into money set aside for bills or savings.', Accents.danger, Icons.block_rounded)
            : (catLeftAfter != null && catLeftAfter < 0)
                ? ('You can, but it puts ${cat!.name} ${m(-catLeftAfter)} over its budget.', Accents.warn, Icons.warning_amber_rounded)
                : dailyAfter * 2 < d.dailySafeSpend
                    ? ('Yes, but it\'s tight: ${m(dailyAfter)}/day left until payday.', Accents.warn, Icons.warning_amber_rounded)
                    : ('Yes! You\'ll still have ${m(after)} (${m(dailyAfter)}/day) until payday.', Accents.savings, Icons.check_circle_rounded);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Can I afford it?', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Spare money right now: ${m(free < 0 ? 0 : free)} · ${m(d.dailySafeSpend)}/day for $days day${days == 1 ? '' : 's'} '
            '(after bills due before payday and money in vaults).', style: context.tt.bodySmall),
        const SizedBox(height: 12),
        AmountField(amount, label: 'Price', autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: what, decoration: const InputDecoration(labelText: 'What is it? (optional, e.g. charger)')),
        const SizedBox(height: 12),
        CategoryPicker(value: category, required: false, onChanged: (v) => setState(() => category = v)),
        if (st != null && st.hasLimit)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${cat!.name}: ${m(st.remaining)} left of ${m(st.budget)} this ${cat.period == 'monthly' ? 'month' : 'week'}', style: context.tt.bodySmall),
          ),
        const SizedBox(height: 16),
        Panel(
          color: color.withValues(alpha: 0.12),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(verdict, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: cents == 0
              ? null
              : () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  openQuickAdd(nav.context, categoryId: category, cents: cents, note: what.text.trim().isEmpty ? null : what.text.trim());
                },
          icon: const Icon(Icons.shopping_bag_rounded),
          label: const Text('I bought it: log it'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Never mind')),
      ]),
    );
  }
}
