/// Model representing handwritten exam marks table data.
/// Supports both table formats:
/// - Type 1: Questions 1, 2, 3, 4
/// - Type 2: Questions 5, 6, 7, 8
/// Rows: Parts a, b, c, d, e, f, g
/// Non-numeric or blank entries are represented as 'N/A' and calculated as 0.
class MarksTableData {
  static const List<String> type1Questions = ['1', '2', '3', '4'];
  static const List<String> type2Questions = ['5', '6', '7', '8'];
  static const List<String> parts = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];

  final List<String> questions;
  final String tableType; // '1-4' or '5-8'

  /// Map of question -> part -> mark string (e.g. marks['1']['a'] = '7' or 'N/A')
  final Map<String, Map<String, String>> cellMarks;

  final Map<String, Map<String, CellOcrResult>> cellResults;

  factory MarksTableData.fromJson(Map<String, dynamic> json,
      {String? imagePath}) {
    final type = json['tableType'] as String;
    if (type != '1-4' && type != '5-8') {
      throw const FormatException('Invalid OCR table type');
    }
    final marks = Map<String, dynamic>.from(json['cellMarks'] as Map).map(
        (q, parts) => MapEntry(
            q,
            Map<String, dynamic>.from(parts as Map).map(
                (p, value) => MapEntry(p, normalizeMark(value as String)))));
    final details = Map<String, dynamic>.from(json['cellResults'] as Map).map(
        (q, parts) => MapEntry(
            q,
            Map<String, dynamic>.from(parts as Map).map((p, value) => MapEntry(
                p,
                CellOcrResult.fromJson(
                    Map<String, dynamic>.from(value as Map))))));
    final expectedQuestions = type == '1-4' ? type1Questions : type2Questions;
    for (final q in expectedQuestions) {
      for (final p in parts) {
        if (marks[q]?[p] == null || details[q]?[p] == null) {
          throw const FormatException('OCR returned an incomplete grid');
        }
        if (details[q]![p]!.isEmpty) marks[q]![p] = 'N/A';
      }
    }
    final score = (json['confidenceScore'] as num).toDouble();
    if (!score.isFinite || score < 0 || score > 1) {
      throw const FormatException('Invalid OCR confidence');
    }
    return MarksTableData(
        tableType: type,
        cellMarks: marks,
        cellResults: details,
        imagePath: imagePath,
        confidenceScore: (json['confidenceScore'] as num).toDouble(),
        scannedAt: DateTime.parse(json['scannedAt'] as String),
        isVerified: false);
  }

  final Map<String, String> detectedTotals;
  final String? detectedGrandTotal;
  final String? imagePath;
  final double confidenceScore;
  final DateTime scannedAt;
  final bool isVerified;

  MarksTableData({
    List<String>? questions,
    String? tableType,
    required this.cellMarks,
    this.cellResults = const {},
    this.detectedTotals = const {},
    this.detectedGrandTotal,
    this.imagePath,
    this.confidenceScore = 0,
    DateTime? scannedAt,
    this.isVerified = false,
  })  : tableType = tableType ?? (questions?.first == '1' ? '1-4' : '5-8'),
        questions =
            questions ?? (tableType == '1-4' ? type1Questions : type2Questions),
        scannedAt = scannedAt ?? DateTime.now();

  static bool isNumericMark(String? text) =>
      text != null && RegExp(r'^[0-9]{1,2}$').hasMatch(text.trim());

  static String normalizeMark(String? text) =>
      isNumericMark(text) ? text!.trim() : 'N/A';

  /// Raw OCR text is retained in cellResults, never used as a displayed mark.
  String getMark(String question, String part) {
    final result = cellResults[question]?[part];
    if (result != null && result.isEmpty && !result.teacherReviewed) {
      return 'N/A';
    }
    return normalizeMark(cellMarks[question]?[part]);
  }

  /// Parses a cell value into numeric marks. 'N/A', blanks or non-numbers evaluate to 0.0.
  static double parseMarkValue(String? text) {
    return isNumericMark(text) ? int.parse(text!.trim()).toDouble() : 0;
  }

  /// Calculates numeric sum of marks for a given question column. 'N/A' is counted as 0.
  double calculateColumnTotal(String question) {
    final colMarks = cellMarks[question];
    if (colMarks == null) return 0.0;
    double sum = 0.0;
    for (final part in parts) {
      final val = colMarks[part];
      sum += parseMarkValue(val);
    }
    return sum;
  }

  /// Calculates the grand total across all questions. 'N/A' is counted as 0.
  double calculateGrandTotal() {
    double grandTotal = 0.0;
    for (final q in questions) {
      grandTotal += calculateColumnTotal(q);
    }
    return grandTotal;
  }

  /// Convenience getter for grand total
  double get grandTotal => calculateGrandTotal();

  MarksTableData copyWith({
    List<String>? questions,
    String? tableType,
    Map<String, Map<String, String>>? cellMarks,
    Map<String, Map<String, CellOcrResult>>? cellResults,
    Map<String, String>? detectedTotals,
    String? detectedGrandTotal,
    String? imagePath,
    double? confidenceScore,
    DateTime? scannedAt,
    bool? isVerified,
  }) {
    final activeTableType = tableType ?? this.tableType;
    final activeQuestions = questions ??
        (activeTableType == '1-4' ? type1Questions : type2Questions);

    return MarksTableData(
      tableType: activeTableType,
      questions: activeQuestions,
      cellMarks: cellMarks ??
          this.cellMarks.map(
                (k, v) => MapEntry(k, Map<String, String>.from(v)),
              ),
      cellResults: cellResults ?? this.cellResults,
      detectedTotals: detectedTotals ?? Map.from(this.detectedTotals),
      detectedGrandTotal: detectedGrandTotal ?? this.detectedGrandTotal,
      imagePath: imagePath ?? this.imagePath,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      scannedAt: scannedAt ?? this.scannedAt,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  /// Factory creating an empty table with all 'N/A' values
  factory MarksTableData.empty({String? imagePath, String tableType = '1-4'}) {
    final questions = tableType == '1-4' ? type1Questions : type2Questions;
    final emptyMap = <String, Map<String, String>>{};
    for (final q in questions) {
      emptyMap[q] = {for (final p in parts) p: 'N/A'};
    }
    return MarksTableData(
      tableType: tableType,
      questions: questions,
      cellMarks: emptyMap,
      imagePath: imagePath,
    );
  }
}

class CellOcrResult {
  final String text;
  final double confidence;
  final bool needsReview;
  final bool teacherReviewed;
  final bool empty;
  final String? reason;
  final String? cropBase64;
  final int? maxMark;
  const CellOcrResult(
      {required this.text,
      required this.confidence,
      required this.needsReview,
      this.teacherReviewed = false,
      this.empty = false,
      this.reason,
      this.cropBase64,
      this.maxMark});
  bool get isEmpty => empty || reason == 'empty_cell';
  bool get needsAttention =>
      !isEmpty && text.trim().isNotEmpty && !MarksTableData.isNumericMark(text);
  factory CellOcrResult.fromJson(Map<String, dynamic> json) => CellOcrResult(
      text: json['text'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      needsReview: json['needs_review'] as bool,
      empty: json['empty'] == true,
      reason: json['reason'] as String?,
      cropBase64: json['crop_base64'] as String?,
      maxMark: json['max_mark'] as int?);
  CellOcrResult reviewed() => CellOcrResult(
      text: text,
      confidence: confidence,
      needsReview: needsReview,
      teacherReviewed: true,
      empty: empty,
      reason: reason,
      cropBase64: cropBase64,
      maxMark: maxMark);
}
