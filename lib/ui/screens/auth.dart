import 'package:material_ui/material_ui.dart';

import '../../clover/clover_widget.dart';
import '../../clover/moods.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../pixel.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final login = TextEditingController(), username = TextEditingController(), email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool signUp = false, busy = false, hide = true;
  String? message;

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final app = context.appRead;
      if (signUp) {
        message = await app.signUp(username.text, email.text, password.text);
      } else {
        await app.signIn(login.text, password.text);
      }
    } catch (e) {
      message = e.toString().replaceAll(RegExp(r'^\w*Exception:?\s*\(?'), '').replaceAll(RegExp(r'\)$'), '');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: CloverSprite(mood: CloverMood.happy, size: 120)),
                    const SizedBox(height: 12),
                    const Center(child: StackdLogo(size: 30)),
                    const SizedBox(height: 10),
                    Text('Your money. Your stack. Clover watching.', textAlign: TextAlign.center, style: TextStyle(color: context.cs.onSurfaceVariant)),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sign in')),
                        ButtonSegment(value: true, label: Text('Create account')),
                      ],
                      selected: {signUp},
                      onSelectionChanged: (s) => setState(() {
                        signUp = s.first;
                        message = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (!signUp)
                      TextFormField(
                        controller: login,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Username or email', prefixIcon: Icon(Icons.person_rounded)),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your username or email' : null,
                      )
                    else ...[
                      TextFormField(
                        controller: username,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.newUsername],
                        decoration: const InputDecoration(
                            labelText: 'Username', prefixIcon: Icon(Icons.alternate_email_rounded), helperText: 'You can sign in with this instead of your email'),
                        validator: (v) => AppState.usernameProblem(v ?? ''),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_rounded)),
                        validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter your email',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      obscureText: hide,
                      autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                            tooltip: hide ? 'Show password' : 'Hide password',
                            onPressed: () => setState(() => hide = !hide),
                            icon: Icon(hide ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                      ),
                      validator: (v) => (v ?? '').length >= 8 ? null : 'At least 8 characters',
                      onFieldSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait...' : (signUp ? 'Create account' : 'Sign in'))),
                    if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!, textAlign: TextAlign.center)),
                    const Divider(height: 40),
                    OutlinedButton(
                      onPressed: () => context.appRead.useLocalOnly(),
                      child: const Text('Use on this device only (no cloud sync)'),
                    ),
                    const SizedBox(height: 6),
                    Text('Local-only data stays on this device. You can sign in later to back it up.',
                        textAlign: TextAlign.center, style: context.tt.bodySmall),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
