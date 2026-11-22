import 'package:material_ui/material_ui.dart';

import 'state/app_state.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await AppState.boot();
  runApp(StackdApp(app: app));
}
