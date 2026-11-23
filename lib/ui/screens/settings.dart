import 'package:material_ui/material_ui.dart';

import '../../clover/kokoro_voice.dart';

import '../../clover/brain.dart';
import '../../clover/clover_widget.dart';
import '../../clover/moods.dart';
import '../../core/dates.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/sync.dart';
import '../../state/app_state.dart';
import '../app.dart';
import '../common.dart';
import '../theme.dart';
import 'auth.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.prefs;
    final d = app.data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: context.wide ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Shell.go(context, 0)),
        automaticallyImplyLeading: false,
      ),
      body: PageBody(children: [
        if (app.signedIn) ...[const Section('Account'), const AccountPanel()],
        Section('Money accounts', trailing: IconButton(onPressed: () => sheet(context, const AccountEditor()), icon: const Icon(Icons.add))),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final a in d.accounts)
              ListTile(
                leading: Icon(accountIcon(a.kind), color: Color(a.color)),
                title: Text(a.name + (a.archived ? ' (archived)' : '')),
                subtitle: Text(a.kind),
                trailing: Money(d.ledger.accountBalance(a.id)),
                onTap: () => sheet(context, AccountEditor(existing: a)),
              ),
            if (d.accounts.isEmpty) const ListTile(title: Text('No accounts. Add cash, Venmo, Cash App, checking...')),
          ]),
        ),
        const Section('General'),
        Panel(
          child: Column(children: [
            TextFormField(
              initialValue: p.displayName,
              decoration: const InputDecoration(labelText: 'Your name (optional)'),
              onFieldSubmitted: (v) => app.savePrefs((x) => x.displayName = v.trim().isEmpty ? null : v.trim()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: p.weekStart,
              decoration: const InputDecoration(labelText: 'Week starts on'),
              items: [for (var i = 1; i <= 7; i++) DropdownMenuItem(value: i, child: Text(weekdayNames[i - 1]))],
              onChanged: (v) => app.savePrefs((x) => x.weekStart = v!),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: 'system', label: Text('System')),
              ],
              selected: {p.theme},
              onSelectionChanged: (v) => app.savePrefs((x) => x.theme = v.first),
            ),
          ]),
        ),
        const Section('Clover'),
        const CloverSettings(),
        const Section('Notifications'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            for (final n in const {
              'payday': 'Payday reminders',
              'bills': 'Upcoming bills',
              'overdue': 'Overdue bills',
              'savings': 'Savings reminders',
              'limits': 'Spending limit warnings (80%)',
              'vacation': 'Vacation milestones',
              'recap': 'Weekly recap ready',
            }.entries)
              SwitchListTile(value: p.notif(n.key), title: Text(n.value), onChanged: (v) => app.savePrefs((x) => x.notifications[n.key] = v)),
            ListTile(
              title: const Text('Quiet hours'),
              subtitle: Text('${p.quietStart}:00 – ${p.quietEnd}:00 (no alerts; reminders move to the end)'),
              trailing: const Icon(Icons.bedtime_rounded),
              onTap: () async {
                final s = await showTimePicker(context: context, initialTime: TimeOfDay(hour: p.quietStart, minute: 0), helpText: 'Quiet from');
                if (s == null || !context.mounted) return;
                final e = await showTimePicker(context: context, initialTime: TimeOfDay(hour: p.quietEnd, minute: 0), helpText: 'Quiet until');
                if (e == null) return;
                app.savePrefs((x) => x
                  ..notifications['quiet_start'] = s.hour
                  ..notifications['quiet_end'] = e.hour);
              },
            ),
          ]),
        ),
        const Section('Sync, backup & privacy'),
        const _DataPanel(),
        const SizedBox(height: 24),
        Center(child: Text('STACKD · no bank connections · your data is private by default', style: context.tt.bodySmall)),
      ]),
    );
  }
}

class CloverSettings extends StatelessWidget {
  const CloverSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.prefs;
    void set(String k, Object v) => app.savePrefs((x) => x.clover[k] = v);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'friendly', label: Text('Friendly')),
            ButtonSegment(value: 'chaotic', label: Text('Chaotic')),
            ButtonSegment(value: 'savage', label: Text('Savage')),
          ],
          selected: {p.personality},
          onSelectionChanged: (v) {
            set('personality', v.first);
            app.refreshHomeClover();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: p.frequency,
          decoration: const InputDecoration(labelText: 'How often Clover reacts'),
          items: const [
            DropdownMenuItem(value: 'low', child: Text('Rarely (important stuff only)')),
            DropdownMenuItem(value: 'normal', child: Text('Normal')),
            DropdownMenuItem(value: 'high', child: Text('Every single thing')),
          ],
          onChanged: (v) => set('frequency', v!),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: p.swearing,
          title: const Text('Clover can swear'),
          subtitle: Text(p.personality == 'friendly'
              ? 'Friendly Clover keeps it clean either way.'
              : p.personality == 'chaotic'
                  ? 'Chaotic: now and then.'
                  : 'Savage: a lot more often.'),
          onChanged: (v) {
            set('swear', v);
            app.refreshHomeClover();
          },
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: p.silent, title: const Text('Silent mode'), subtitle: const Text('No sounds at all'), onChanged: (v) => set('silent', v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: p.voiceMuted, title: const Text('Mute voice'), subtitle: const Text('Replay buttons still play'), onChanged: (v) => set('muted', v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: p.subtitles, title: const Text('Subtitles'), onChanged: (v) => set('subtitles', v)),
        const SizedBox(height: 8),
        const Text('Clover\'s voice'),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'clover', label: Text('Clover'), icon: Icon(Icons.pets_rounded)),
            ButtonSegment(value: 'talk', label: Text('Device'), icon: Icon(Icons.record_voice_over_rounded)),
            ButtonSegment(value: 'babble', label: Text('Gibberish'), icon: Icon(Icons.graphic_eq_rounded)),
          ],
          selected: {p.voiceStyle},
          onSelectionChanged: (v) => set('voice', v.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(switch (p.voiceStyle) {
            'clover' => 'Clover\'s own voice, made on your device by a free open-source speech model (Kokoro, Apache-2.0). '
                'It\'s tuned to sound young and mischievous, but it is not a recorded voice actor.',
            'talk' => 'Says his lines with your device\'s built-in voice, pitched up.',
            _ => 'Cartoon gibberish, like a video game character.',
          }, style: context.tt.bodySmall),
        ),
        if (p.voiceStyle == 'clover') const CloverVoicePanel(),
        Row(children: [
          const Icon(Icons.volume_down_rounded),
          Expanded(child: Slider(value: p.voiceVolume.toDouble(), max: 100, divisions: 20, label: '${p.voiceVolume}', onChanged: (v) => set('volume', v.round()))),
          IconButton(
            tooltip: 'Test voice',
            onPressed: () => app.speak(const CloverSays('test', 'test', CloverMood.excited, 'Hey! Testing testing. Money money money!'), force: true),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ]),
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodGallery())),
          icon: const Icon(Icons.emoji_emotions_rounded),
          label: const Text('Clover mood gallery'),
        ),
      ]),
    );
  }
}

class MoodGallery extends StatelessWidget {
  const MoodGallery({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Clover moods')),
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Motion and effects are live. Dedicated expression art for each mood is listed in docs/CLOVER_ASSETS.md; '
                'until a mood\'s sprite is added, Clover uses the original reference sprite.'),
          ),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 180,
              padding: const EdgeInsets.all(12),
              children: [
                for (final mood in CloverMood.values)
                  Column(children: [
                    Expanded(child: CloverSprite(mood: mood, size: 90, talking: context.app.talking, onTap: () => context.appRead.speak(CloverSays('g', 'g', mood, mood.label), force: true))),
                    Text(mood.label, textAlign: TextAlign.center),
                  ]),
              ],
            ),
          ),
        ]),
      );
}

class _DataPanel extends StatelessWidget {
  const _DataPanel();
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final sync = app.sync;
    final status = !cloudConfigured
        ? 'Cloud sync not configured in this build (local only).'
        : !app.signedIn
            ? 'Not signed in · data stays on this device.'
            : switch (sync!.state) {
                SyncState.syncing => 'Syncing...',
                SyncState.error => 'Sync failed, will retry: ${sync.lastError}',
                _ => 'Synced${sync.lastSynced != null ? ' at ${TimeOfDay.fromDateTime(sync.lastSynced!).format(context)}' : ''}',
              };
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        ListTile(
          leading: Icon(app.signedIn ? Icons.cloud_done_rounded : Icons.cloud_off_rounded),
          title: Text(status),
          subtitle: Text('${app.pendingSync} change(s) waiting to upload'),
          trailing: app.signedIn ? IconButton(onPressed: () => app.sync?.sync(), icon: const Icon(Icons.sync)) : null,
        ),
        if (cloudConfigured && !app.signedIn)
          ListTile(
            leading: const Icon(Icons.login_rounded),
            title: const Text('Sign in to back up & sync'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(body: AuthScreen()))),
          ),
        ListTile(
          leading: const Icon(Icons.restart_alt_rounded),
          title: const Text('Start fresh'),
          subtitle: const Text('Clear all money activity. Keeps accounts, bills, goals and budgets.'),
          onTap: () async {
            final choice = await showDialog<String>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Start fresh?'),
                content: const Text('Every transaction, payment and split is undone (kept in history, not counted). '
                    'Accounts, bills, goals and budgets stay. Afterwards, use "Set the money I have" on Home.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, 'all'), child: const Text('Clear savings too')),
                  FilledButton(onPressed: () => Navigator.pop(c, 'keep'), child: const Text('Keep my vault savings')),
                ],
              ),
            );
            if (choice == null) return;
            app.startFresh(keepSavings: choice == 'keep');
            if (context.mounted) context.toast('Fresh start. Now set the money you have on Home.');
          },
        ),        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: const Text('Export my data (JSON)'),
          onTap: () async {
            final path = await app.exportJson();
            if (context.mounted) context.toast('Saved to $path');
          },
        ),
        if (!app.signedIn && app.localOnlyChosen)
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: Text(app.signedIn ? 'Sign out' : 'Leave local-only mode'),
            subtitle: const Text('Removes financial data from this device'),
            onTap: () async {
              final pending = app.pendingSync;
              final warn = !app.signedIn
                  ? 'Local-only data is not backed up anywhere. Export first if you want to keep it. It will be erased from this device.'
                  : pending > 0
                      ? '$pending change(s) have not uploaded yet and will be lost. Sync first if you can.'
                      : 'Your data stays in your cloud account and is removed from this device.';
              if (await confirm(context, 'Sign out?', warn, ok: 'Sign out', danger: pending > 0 || !app.signedIn)) await app.signOut();
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_forever_rounded, color: Accents.danger),
          title: const Text('Delete account & all data', style: TextStyle(color: Accents.danger)),
          onTap: () async {
            if (!await confirm(context, 'Delete everything?',
                'This permanently deletes your STACKD account, every transaction, vault, bill and setting${app.signedIn ? ' from the cloud and' : ''} from this device. This cannot be undone.',
                ok: 'Continue', danger: true)) {
              return;
            }
            if (!context.mounted) return;
            if (!await confirm(context, 'Last chance', 'Really delete all STACKD data permanently?', ok: 'Delete forever', danger: true)) return;
            try {
              await app.deleteAccount();
            } catch (e) {
              if (context.mounted) context.toast('Delete failed: $e');
            }
          },
        ),
      ]),
    );
  }
}

class AccountEditor extends StatefulWidget {
  final MoneyAccount? existing;
  const AccountEditor({super.key, this.existing});
  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  final form = GlobalKey<FormState>();
  late final a = widget.existing ?? MoneyAccount(id: newId(), name: '');
  late final name = TextEditingController(text: a.name);
  final balance = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final isNew = widget.existing == null;
    final current = isNew ? 0 : app.data.ledger.accountBalance(a.id);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'New money account' : 'Edit account', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in MoneyAccount.kinds)
              ChoiceChip(
                avatar: Icon(accountIcon(k), size: 16),
                label: Text(const {'cash': 'Cash', 'venmo': 'Venmo', 'cashapp': 'Cash App', 'checking': 'Checking', 'savings': 'Savings', 'custom': 'Custom'}[k]!),
                selected: a.kind == k,
                onSelected: (_) => setState(() {
                  a.kind = k;
                  if (name.text.isEmpty || const ['Cash', 'Venmo', 'Cash App', 'Checking', 'Savings'].contains(name.text)) {
                    name.text = const {'cash': 'Cash', 'venmo': 'Venmo', 'cashapp': 'Cash App', 'checking': 'Checking', 'savings': 'Savings', 'custom': ''}[k]!;
                  }
                }),
              ),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Name it' : null),
          const SizedBox(height: 12),
          TextFormField(
            controller: balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: isNew ? 'Starting balance' : 'Actual balance now (optional: records an adjustment)',
              prefixText: '\$ ',
              helperText: isNew ? null : 'STACKD says ${m(current)}',
            ),
            validator: (v) => (v ?? '').trim().isEmpty || parseCents(v!) != null ? null : 'Invalid amount',
          ),
          const Section('Color'),
          ColorChooser(value: a.color, onChanged: (v) => setState(() => a.color = v)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              a.name = name.text.trim();
              final entered = parseCents(balance.text);
              if (isNew) {
                a.sort = app.data.accounts.length;
                app.createAccount(a, entered ?? 0);
              } else {
                final diff = entered == null ? 0 : entered - current;
                app.record([if (diff != 0) app.event(kind: 'adjustment', amountCents: diff, accountId: a.id, note: 'Balance correction')], also: [a]);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
          if (!isNew)
            TextButton(
              onPressed: () {
                a.archived = !a.archived;
                app.save(a);
                Navigator.pop(context);
              },
              child: Text(a.archived ? 'Unarchive' : 'Archive (keeps history and balance)'),
            ),
          if (!isNew)
            DeleteButton(
              what: a.name,
              body: current == 0
                  ? 'Removes this account. Its history stays in Activity.'
                  : 'This account shows ${m(current)}. Deleting it removes that from your total money (transactions stay in history). If it was a duplicate, that is what you want.',
              toDelete: () => [a],
            ),
        ]),
      ),
    );
  }
}

/// Download / pick / preview / remove Clover's offline character voice.
class CloverVoicePanel extends StatefulWidget {
  const CloverVoicePanel({super.key});
  @override
  State<CloverVoicePanel> createState() => _CloverVoicePanelState();
}

class _CloverVoicePanelState extends State<CloverVoicePanel> {
  bool? installed;
  double? progress; // non-null while downloading
  bool unpacking = false;
  String? error;

  static const _previews = [
    'PAYDAY! Okay okay, bills first. Then we party. A little.',
    '*whispers* psst. Insurance is due Friday. Don\'t let it sneak up on you.',
    'Heh heh. Five drive-thrus this week? I\'m not mad. I\'m impressed.',
    'WHO AUTHORIZED THIS?! The fun budget is GONE!',
  ];
  int previewIndex = 0;

  @override
  void initState() {
    super.initState();
    KokoroVoice.instance.installed.then((v) {
      if (mounted) setState(() => installed = v);
    });
  }

  Future<void> download() async {
    setState(() {
      progress = 0;
      error = null;
    });
    try {
      await KokoroVoice.instance.install(progress: (v) {
        if (!mounted) return;
        setState(() {
          progress = v;
          unpacking = v >= 1;
        });
      });
      if (mounted) setState(() => installed = true);
    } catch (e) {
      if (mounted) setState(() => error = 'Download failed. Check your connection and try again.');
    } finally {
      if (mounted) {
        setState(() {
          progress = null;
          unpacking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.prefs;
    void set(String k, Object v) => app.savePrefs((x) => x.clover[k] = v);
    if (installed == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    if (progress != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: unpacking ? null : progress),
          const SizedBox(height: 6),
          Text(unpacking ? 'Unpacking... (about a minute)' : 'Downloading Clover\'s voice... ${(progress! * 100).round()}%',
              style: context.tt.bodySmall),
        ]),
      );
    }
    if (installed == false) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(
              onPressed: download, icon: const Icon(Icons.download_rounded), label: const Text('Download Clover\'s voice (132 MB, one time)')),
          const SizedBox(height: 4),
          Text('After that it works offline. Until then Clover uses the device voice.', style: context.tt.bodySmall),
          if (error != null) Text(error!, style: const TextStyle(color: Accents.danger)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('Pitch'),
          Expanded(
            child: Slider(
                value: p.voicePitch.clamp(1.0, 1.35), min: 1.0, max: 1.35, divisions: 7,
                label: p.voicePitch.toStringAsFixed(2), onChanged: (v) => set('voice_pitch', v)),
          ),
        ]),
        FilledButton.tonalIcon(
          onPressed: () {
            final line = _previews[previewIndex++ % _previews.length];
            app.speak(CloverSays('preview', 'preview', CloverMood.excited, line), force: true);
            context.toast(line.replaceAll(RegExp(r'\*[^*]*\*\s*'), '(whispers) '));
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Preview Clover\'s voice'),
        ),
        Text('The first time a line is spoken takes a moment; after that it\'s instant.', style: context.tt.bodySmall),
        TextButton(
          onPressed: () async {
            if (!await confirm(context, 'Remove voice?', 'Frees about 145 MB. Clover goes back to the device voice until you download it again.')) return;
            await KokoroVoice.instance.uninstall();
            if (mounted) setState(() => installed = false);
          },
          child: const Text('Remove voice (free up space)'),
        ),
      ]),
    );
  }
}
/// Signed-in account: username (add / change), email, log out.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key});
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  late final ctl = TextEditingController(text: context.appRead.prefs.username ?? '');
  bool busy = false;
  String? error;

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.appRead.setUsername(ctl.text);
      if (mounted) context.toast('Username saved. You can sign in with it now.');
    } catch (e) {
      error = e.toString().replaceAll(RegExp(r'^\w*Exception:?\s*'), '');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final current = app.prefs.username;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.mail_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(app.accountEmail ?? '', overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: ctl,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: current == null ? 'Pick a username' : 'Username',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                helperText: current == null ? 'Then you can sign in with it instead of your email' : 'Sign in with this or your email',
                errorText: error,
              ),
              onSubmitted: (_) => save(),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton(onPressed: busy ? null : save, child: Text(busy ? '...' : 'Save')),
          ),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Log out'),
          onPressed: () async {
            final pending = app.pendingSync;
            final warn = pending > 0
                ? '$pending change(s) have not uploaded yet and will be lost. Wait a moment for them to sync first.'
                : 'Your money stays safe in your account. This device is cleared until you sign in again.';
            if (await confirm(context, 'Log out?', warn, ok: 'Log out', danger: pending > 0)) await app.signOut();
          },
        ),
      ]),
    );
  }
}