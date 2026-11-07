import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_message/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MeshMessage UI renders without a backend', (tester) async {
    await tester.pumpWidget(const MeshMessageApp());
    await tester.pump();

    expect(find.text('MeshMessage'), findsOneWidget);
    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.text('Local profile · No account required'), findsOneWidget);
    expect(find.text('Save profile'), findsOneWidget);
  });
}
