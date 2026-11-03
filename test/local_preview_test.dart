import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/app.dart';
import 'package:my_app/services/local_preview_services.dart';

void main() {
  testWidgets('local preview opens the app without Supabase initialized',
      (tester) async {
    await tester.pumpWidget(MarkSheetApp(
      authService: LocalPreviewAuthService(),
      workflowRepository: LocalPreviewWorkflowRepository(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Welcome, Local Preview Admin'), findsOneWidget);

    await tester.tap(find.text('Manage courses'));
    await tester.pumpAndSettle();
    expect(find.text('CSE3200 · Software Engineering'), findsOneWidget);
  });
}
