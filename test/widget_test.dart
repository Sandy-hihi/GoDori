import 'package:flutter_test/flutter_test.dart';
import 'package:boardpad/main.dart';

void main() {
  testWidgets('손님과 관리자 진입 화면이 표시된다', (tester) async {
    await tester.pumpWidget(const GodoriApp());
    expect(find.text('손님용 패드 켜기'), findsOneWidget);
    expect(find.text('관리자 대시보드 켜기'), findsOneWidget);
  });
}
