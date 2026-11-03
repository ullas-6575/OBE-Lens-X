import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'workflow/repository.dart';

void bootstrap({
  AuthService? authService,
  WorkflowRepository? workflowRepository,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MarkSheetApp(
    authService: authService,
    workflowRepository: workflowRepository,
  ));
}
