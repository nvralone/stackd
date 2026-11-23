// Shared widgets and helpers.
import 'package:material_ui/material_ui.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'pixel.dart';
import 'theme.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension Ctx on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  bool get wide => MediaQuery.sizeOf(this).width >= 900;
  void toast(String msg) => ScaffoldMessenger.of(this)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

String m(int cents) => formatCents(cents);

class Money extends StatelessWidget {
  final int cents;
  final double size;
  final Color? color;
  final bool sign;
  const Money(this.cents, {super.key, this.size = 16, this.color, this.sign = false});
  @override
  Widget build(BuildContext context) => Text(formatCents(cents, showPlus: sign),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]));
}

class Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const Section(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: PixelText(title, size: 12)))),
          ?trailing,
        ]),
      );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  @override
  Widget build(BuildContext context) => Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class Stat extends StatelessWidget {
  final String label;
  final int cents;
  final Color? color;
  final IconData? icon;
  final String? hint;
  final VoidCallback? onTap;
  const Stat(this.label, this.cents, {super.key, this.color, this.icon, this.hint, this.onTap});
  @override
  Widget build(BuildContext context) => Panel(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null)
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: (color ?? context.cs.primary).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: color ?? context.cs.primary),
              ),
            if (icon != null) const SizedBox(width: 8),
            Expanded(child: Text(label, style: context.tt.labelMedium?.copyWith(color: context.cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Money(cents, size: 20, color: color)),
          if (hint != null) Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
        ]),
      );
}

class Bar extends StatelessWidget {
  final int value, max;
  final Color color;
  final double height;
  const Bar(this.value, this.max, {super.key, required this.color, this.height = 8});
  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (value.clamp(0, max) / max);
    return PixelBar(f, color: color, height: height < 10 ? 10 : height, danger: max > 0 && value > max);
  }
}

class Empty extends StatelessWidget {
  final String text;
  final IconData icon;
  final Widget? action;
  const Empty(this.text, {super.key, this.icon = Icons.inbox_rounded, this.action});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          Icon(icon, size: 40, color: context.cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.cs.onSurfaceVariant)),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 12), child: action),
        ]),
      );
}

/// Amount input that only ever produces integer cents.
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus, allowNegative;
  final ValueChanged<String>? onChanged;
  const AmountField(this.controller, {super.key, this.label = 'Amount', this.autofocus = false, this.allowNegative = false, this.onChanged});
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: allowNegative),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        decoration: InputDecoration(labelText: label, prefixText: '\$ '),
        validator: (v) {
          final c = parseCents(v ?? '');
          if (c == null) return 'Enter an amount like 12.50';
          if (!allowNegative && c <= 0) return 'Must be more than \$0';
          if (c == 0) return 'Cannot be zero';
          return null;
        },
      );
}

class AccountPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? exclude;
  const AccountPicker({super.key, required this.value, required this.onChanged, this.label = 'Account', this.exclude});
  @override
  Widget build(BuildContext context) {
    final accts = context.app.data.accounts.where((a) => !a.archived && a.id != exclude).toList();
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: accts.any((a) => a.id == value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final a in accts)
          DropdownMenuItem(value: a.id, child: Row(children: [Icon(accountIcon(a.kind), size: 18, color: Color(a.color)), const SizedBox(width: 8), Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis))])),
      ],
      onChanged: onChanged,
      validator: (v) => v == null ? 'Pick an account' : null,
    );
  }
}

class CategoryPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;
  const CategoryPicker({super.key, required this.value, required this.onChanged, this.required = true});
  @override
  Widget build(BuildContext context) {
    final cats = context.app.data.categories.where((c) => !c.archived || c.id == value).toList();
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: cats.any((c) => c.id == value) ? value : null,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        for (final c in cats)
          DropdownMenuItem(value: c.id, child: Row(children: [CatDot(c), const SizedBox(width: 8), Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis))])),
      ],
      onChanged: onChanged,
      validator: (v) => required && v == null ? 'Pick a category' : null,
    );
  }
}

class CatDot extends StatelessWidget {
  final Category c;
  final double size;
  const CatDot(this.c, {super.key, this.size = 20});
  @override
  Widget build(BuildContext context) => Container(
        width: size + 10,
        height: size + 10,
        decoration: BoxDecoration(color: Color(c.color).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
        child: Icon(categoryIcons[c.icon.clamp(0, categoryIcons.length - 1)], size: size * 0.8, color: Color(c.color)),
      );
}

class DateField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String label;
  final bool clearable;
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Date', this.clearable = false});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
              context: context, initialDate: value ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
          if (d != null) onChanged(dateOnly(d));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: clearable && value != null
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
                : const Icon(Icons.calendar_today_rounded, size: 18),
          ),
          child: Text(value == null ? 'None' : '${weekdayNames[value!.weekday - 1]}, ${prettyDate(value!)} ${value!.year}'),
        ),
      );
}

class ColorChooser extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const ColorChooser({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in pickColors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Color(c), shape: BoxShape.circle,
                  border: Border.all(color: c == value ? context.cs.onSurface : Colors.transparent, width: 3)),
            ),
          ),
      ]);
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Confirm', bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: Accents.danger) : null,
              onPressed: () => Navigator.pop(c, true),
              child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// ⋮ menu with Edit, optional extra actions, and Delete (always confirmed first).
class ItemMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final String what, deleteBody;
  final List<Entity> Function() toDelete;
  final VoidCallback? afterDelete;
  final List<(String, IconData, VoidCallback)> extra;
  const ItemMenu({super.key, required this.onEdit, required this.what, required this.deleteBody, required this.toDelete,
      this.afterDelete, this.extra = const []});

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
        tooltip: 'Options',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (i) async {
          if (i == 0) return onEdit();
          if (i > 0) return extra[i - 1].$3();
          final app = context.appRead;
          if (!await confirm(context, 'Delete $what?', deleteBody, ok: 'Delete', danger: true)) return;
          app.deleteItems(toDelete());
          afterDelete?.call();
          if (context.mounted) context.toast('Deleted $what.');
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 0, child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'))),
          for (var i = 0; i < extra.length; i++)
            PopupMenuItem(value: i + 1, child: ListTile(leading: Icon(extra[i].$2), title: Text(extra[i].$1))),
          const PopupMenuItem(
              value: -1, child: ListTile(leading: Icon(Icons.delete_rounded, color: Accents.danger), title: Text('Delete', style: TextStyle(color: Accents.danger)))),
        ],
      );
}

/// Red delete button for the bottom of editor sheets.
class DeleteButton extends StatelessWidget {
  final String what, body;
  final List<Entity> Function() toDelete;
  final int pops;
  const DeleteButton({super.key, required this.what, required this.body, required this.toDelete, this.pops = 1});
  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Accents.danger),
        icon: const Icon(Icons.delete_rounded),
        label: Text('Delete $what'),
        onPressed: () async {
          final app = context.appRead;
          final nav = Navigator.of(context);
          if (!await confirm(context, 'Delete $what?', body, ok: 'Delete', danger: true)) return;
          app.deleteItems(toDelete());
          for (var i = 0; i < pops && nav.canPop(); i++) {
            nav.pop();
          }
        },
      );
}

Future<T?> sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: child),
    );

/// Standard scrollable page body with max width for desktop.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: children),
        ),
      );
}

String kindLabel(String kind) => switch (kind) {
      'opening' => 'Starting balance',
      'adjustment' => 'Adjustment',
      'income' => 'Income',
      'refund' => 'Refund',
      'expense' => 'Expense',
      'transfer' => 'Transfer',
      'goal_deposit' => 'Saved',
      'goal_withdraw' => 'Savings withdrawal',
      'bill_payment' => 'Bill payment',
      'loan_out' => 'Lent money',
      'loan_in' => 'Repayment received',
      'reversal' => 'Reversal',
      _ => kind,
    };

String sourceLabel(String? s) => switch (s) {
      'paycheck' => 'Paycheck',
      'side_job' => 'Side job',
      'tip' => 'Tips',
      'gift' => 'Gift',
      'sale' => 'Sold item',
      'loan' => 'Borrowed',
      _ => 'Other',
    };

String freqLabel(String f) => switch (f) {
      'once' => 'One time',
      'weekly' => 'Weekly',
      'biweekly' => 'Every 2 weeks',
      'semimonthly' => 'Twice a month',
      'monthly' => 'Monthly',
      'yearly' => 'Yearly',
      'irregular' => 'Irregular',
      'payday' => 'Each payday',
      'none' => 'No schedule',
      _ => f,
    };

/// Signed display amount of an event for lists (account perspective).
int displayDelta(LedgerEvent e) => switch (e.kind) {
      'income' || 'refund' || 'loan_in' => e.amountCents,
      'opening' || 'adjustment' => e.amountCents,
      'expense' || 'bill_payment' || 'loan_out' => -e.amountCents,
      _ => e.amountCents,
    };
