// Basic smoke test for the MyShop app.
//
// It replaces the default counter test that `flutter create` generated,
// which referenced a `MyApp` class that does not exist in this project.

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('MyShop app builds and shows its start screen', (tester) async {
    // Build the real app and trigger a frame.
    await tester.pumpWidget(const ShopApp());

    // The store starts in the 'loading' state, so the startup screen is shown
    // until data arrives from the server.
    expect(find.text('Loading shop...'), findsOneWidget);
  });
}