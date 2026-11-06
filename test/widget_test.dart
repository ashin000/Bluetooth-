import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_message/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firebaseReady = false;
  });

  testWidgets('MeshMessage opens in guest mode when Firebase is unavailable',
      (tester) async {
    await tester.pumpWidget(const MeshMessageApp());
    await tester.pumpAndSettle();

    expect(find.text('MeshMessage'), findsOneWidget);
    expect(find.text('Offline guest session'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
  });
}
