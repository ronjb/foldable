import 'package:flutter_test/flutter_test.dart';

import 'package:foldable_example/main.dart';

void main() {
  testWidgets('example app builds and shows the device card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FoldableExampleApp());
    await tester.pump();

    expect(find.text('Device'), findsOneWidget);
    // Below the Device card, past the bottom of the 800×600 test window.
    expect(find.text('Hinge angle', skipOffstage: false), findsOneWidget);
  });
}
