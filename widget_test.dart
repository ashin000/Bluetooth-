import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_message/main.dart';

void main() {
  testWidgets('MeshMessage home screen renders', (tester) async {
    await tester.pumpWidget(const MeshMessageApp());
    expect(find.text('MeshMessage'), findsOneWidget);
    expect(find.text(''Hybrid Bluetooth + LoRa prototype v0.2''), findsOneWidget);
  });
}
