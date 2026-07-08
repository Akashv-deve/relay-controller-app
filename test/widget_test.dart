import 'package:flutter_test/flutter_test.dart';

// Make sure this matches your actual project name!
import 'package:relay_control/main.dart'; 

void main() {
  testWidgets('SmartRelayApp loads correctly smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartRelayApp());

    // Verify that our app booted up and the AppBar title exists.
    expect(find.text('Room Controls'), findsOneWidget);

    // Verify that our main sections rendered properly.
    expect(find.text('Scenes'), findsOneWidget);
    expect(find.text('Appliance Control'), findsOneWidget);
  });
}