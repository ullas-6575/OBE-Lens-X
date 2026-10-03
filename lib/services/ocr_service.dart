import '../models/marks_table_data.dart';

/// Service interface for Optical Character Recognition on marks tables
abstract class BaseOcrService {
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    void Function(String status, double progress)? onProgress,
  });
}

/// Default until an OCR model is connected. Keeps manual review available.
/// Implement [BaseOcrService] and inject it through MarkSheetApp.ocrService
/// to provide extracted marks without changing the screens.
class PlaceholderOcrService implements BaseOcrService {
  const PlaceholderOcrService();

  @override
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Preparing marks table...', 0.15);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    onProgress?.call('Initializing grid...', 0.80);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final data = MarksTableData.empty(
      imagePath: imagePath,
      tableType: tableType,
    ).copyWith(confidenceScore: 0);
    onProgress?.call('Complete.', 1.0);
    return data;
  }
}

/// Simulated OCR Service for fast testing without invoking native binaries
class MockOcrService implements BaseOcrService {
  final Duration stepDuration;
  final MarksTableData? overrideData;

  const MockOcrService({
    this.stepDuration = const Duration(milliseconds: 100),
    this.overrideData,
  });

  @override
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Processing image...', 0.5);
    if (stepDuration > Duration.zero) await Future.delayed(stepDuration);
    onProgress?.call('Extraction complete!', 1.0);

    return overrideData ??
        MarksTableData.empty(
          imagePath: imagePath,
          tableType: tableType,
        );
  }
}
