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
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
