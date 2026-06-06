import 'package:flutter_test/flutter_test.dart';
import 'package:delimap/main_app.dart';

void main() {
  testWidgets('DeliMap app loading smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DeliMapApp());

    // Verify that the logo title is present
    expect(find.text('DELIMAP'), findsOneWidget);
    expect(find.text('Scan. Route. Deliver.'), findsOneWidget);
  });
}
