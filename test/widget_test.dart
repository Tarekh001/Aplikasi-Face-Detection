// Basic smoke test for the ASNG app
import 'package:flutter_test/flutter_test.dart';
import 'package:asng/main.dart';

void main() {
  testWidgets('App renders home page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(cameras: []));
    expect(find.text('Sistem Presensi Untuk ASN\nKab Tangerang'), findsOneWidget);
    expect(find.text('Presensi'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });
}
