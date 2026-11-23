import 'package:flutter_test/flutter_test.dart';
import 'package:stackd/data/models.dart';
import 'package:stackd/state/app_state.dart';

void main() {
  test('username rules: 3-20 of a-z 0-9 _ . (any case)', () {
    expect(AppState.usernameProblem('isaac'), isNull);
    expect(AppState.usernameProblem('Isaac_70'), isNull);
    expect(AppState.usernameProblem('a.b'), isNull);
    expect(AppState.usernameProblem('ab'), isNotNull);
    expect(AppState.usernameProblem('has space'), isNotNull);
    expect(AppState.usernameProblem('me@mail.com'), isNotNull);
    expect(AppState.usernameProblem('x' * 21), isNotNull);
  });

  test('a device that has not heard about the username never sends a blank one', () {
    final p = Prefs(id: 'u1');
    expect(p.toRow().containsKey('username'), isFalse); // left alone on the server
    p.username = 'isaac';
    expect(p.toRow()['username'], 'isaac');
    expect(Prefs.fromRow(p.toRow()).username, 'isaac');
  });
}
