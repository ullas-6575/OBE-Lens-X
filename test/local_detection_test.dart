import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/table_selection.dart';
import 'package:my_app/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Local detector invokes native pipeline and preserves manual fallback',
      () async {
    const channel = MethodChannel('com.example.my_app/local_ocr');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final selection = TableSelection.initial().rotateClockwise();
    var detected = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'detectTable');
      expect(call.arguments, {'imagePath': 'photo.jpg', 'rotation': 90});
      return {'detected': detected, ...selection.toJson()};
    });
    try {
      const service = LocalOcrService();
      expect(
          (await service.detectTable(imagePath: 'photo.jpg', rotation: 90))!
              .toJson(),
          selection.toJson());
      detected = false;
      expect(await service.detectTable(imagePath: 'photo.jpg', rotation: 90),
          isNull);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
