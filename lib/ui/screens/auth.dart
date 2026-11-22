import 'package:material_ui/material_ui.dart';

import '../../clover/clover_widget.dart';
import '../../clover/moods.dart';
import '../common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool signUp = false, busy = false;
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
        message = await app.signUp(email.text.trim(), password.text);
      } else {
        await app.signIn(email.text.trim(), password.text);
      }
    } catch (e) {
      message = e.toString().replaceAll(RegExp(r'^\w*Exception\(?'), '');
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
              child: Form(
                key: form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: CloverSprite(mood: CloverMood.happy, size: 120)),
                  const SizedBox(height: 8),
                  Text('STACKD', textAlign: TextAlign.center, style: context.tt.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 4)),
                  Text('Your money. Your stack. Clover watching.', textAlign: TextAlign.center, style: TextStyle(color: context.cs.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v ?? '').length >= 8 ? null : 'At least 8 characters',
                    onFieldSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait...' : (signUp ? 'Create account' : 'Sign in'))),
                  TextButton(
                      onPressed: () => setState(() => signUp = !signUp),
                      child: Text(signUp ? 'Have an account? Sign in' : 'New here? Create an account')),
                  if (message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message!, textAlign: TextAlign.center)),
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
      );
}
