import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';
import 'image_source_screen.dart';

class VerificationScreen extends StatefulWidget {
  final MarksTableData marksTableData;
  final String? imagePath;
  final bool isSampleDemo;

  const VerificationScreen({
    super.key,
    required this.marksTableData,
    this.imagePath,
    this.isSampleDemo = false,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late String _activeTableType; // '1-4' or '5-8'
  late List<String> _activeQuestions;
  late Map<String, Map<String, TextEditingController>> _controllers;

  static const List<String> _allQuestions = [
    '1', '2', '3', '4', '5', '6', '7', '8'
  ];

  @override
  void initState() {
    super.initState();
    _activeTableType = widget.marksTableData.tableType;
    _activeQuestions = _activeTableType == '1-4'
        ? MarksTableData.type1Questions
        : MarksTableData.type2Questions;
    _initControllers();
  }

  void _initControllers() {
    _controllers = {};
    for (final q in _allQuestions) {
      _controllers[q] = {};
      for (final p in MarksTableData.parts) {
        String initialVal = widget.marksTableData.getMark(q, p);
        if (initialVal.trim().isEmpty) {
          initialVal = 'N/A';
        }
        _controllers[q]![p] = TextEditingController(text: initialVal);
      }
    }
  }

  @override
  void dispose() {
    for (final q in _allQuestions) {
      for (final p in MarksTableData.parts) {
        _controllers[q]?[p]?.dispose();
      }
    }
    super.dispose();
  }

  void _switchTableType(String type) {
    setState(() {
      _activeTableType = type;
      _activeQuestions = type == '1-4'
          ? MarksTableData.type1Questions
          : MarksTableData.type2Questions;
    });
  }

  double _calculateColTotal(String question) {
    double total = 0.0;
    for (final p in MarksTableData.parts) {
      final val = _controllers[question]?[p]?.text.trim() ?? '';
      total += MarksTableData.parseMarkValue(val);
    }
    return total;
  }

  double _calculateGrandTotal() {
    double grand = 0.0;
    for (final q in _activeQuestions) {
      grand += _calculateColTotal(q);
    }
    return grand;
  }

  String _formatNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  void _resetToDetected() {
    setState(() {
      for (final q in _allQuestions) {
        for (final p in MarksTableData.parts) {
          final val = widget.marksTableData.getMark(q, p);
          _controllers[q]![p]?.text = val.trim().isEmpty ? 'N/A' : val;
        }
      }
    });
  }

  void _setAllToNA() {
    setState(() {
      for (final q in _activeQuestions) {
        for (final p in MarksTableData.parts) {
          _controllers[q]![p]?.text = 'N/A';
        }
      }
    });
  }

  void _submitVerification() {
    final Map<String, Map<String, String>> updatedMarks = {};
    for (final q in _activeQuestions) {
      updatedMarks[q] = {};
      for (final p in MarksTableData.parts) {
        final raw = _controllers[q]?[p]?.text.trim() ?? '';
        final isNumeric = double.tryParse(raw) != null;
        updatedMarks[q]![p] = isNumeric ? raw : 'N/A';
      }
    }

    final verifiedData = widget.marksTableData.copyWith(
      tableType: _activeTableType,
      questions: _activeQuestions,
      cellMarks: updatedMarks,
      isVerified: true,
    );

    _showVerificationSuccessDialog(verifiedData);
  }

  void _showVerificationSuccessDialog(MarksTableData data) {
    final grandTotal = _calculateGrandTotal();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              const SizedBox(height: 20),
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Colors.green,
                  size: 42,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Marks Verified & Computed!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Table ${_activeTableType == '1-4' ? 'Questions 1–4' : 'Questions 5–8'} verified. Non-numeric marks calculated as 0.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),

              // Summary Breakdown Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    for (final q in _activeQuestions) ...[
                      _buildSummaryRow(
                        'Question $q Total',
                        _formatNumber(_calculateColTotal(q)),
                      ),
                      const Divider(height: 14),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Grand Total',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            _formatNumber(grandTotal),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action button to scan another
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const ImageSourceScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text('Scan Another Mark Sheet'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  void _showEnlargedImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildThumbnailImage(
                height: 420,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailImage({
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
  }) {
    final hasLocalFile = !kIsWeb &&
        widget.imagePath != null &&
        File(widget.imagePath!).existsSync();

    if (hasLocalFile) {
      return Image.file(
        File(widget.imagePath!),
        height: height,
        width: width,
        fit: fit,
      );
    }

    return Image.asset(
      'assets/sample_marksheet.png',
      height: height,
      width: width,
      fit: fit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final grandTotal = _calculateGrandTotal();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Handwritten Marks'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'reset') _resetToDetected();
              if (val == 'na') _setAllToNA();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restore_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Reset to Detected'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'na',
                child: Row(
                  children: [
                    Icon(Icons.clear_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Set Blank/All to N/A'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Thumbnail Preview Card
                    InkWell(
                      onTap: () => _showEnlargedImage(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _buildThumbnailImage(
                                height: 68,
                                width: 88,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${(widget.marksTableData.confidenceScore * 100).toStringAsFixed(1)}% OCR Accuracy',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Original MarkSheet Image',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Tap to enlarge & inspect handwritten ink',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.zoom_in_rounded,
                              color: colorScheme.primary,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Table Type Switcher (Questions 1–4 vs Questions 5–8)
                    Row(
                      children: [
                        Text(
                          'Table Format:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: '1-4',
                                label: Text('Q1 – Q4'),
                              ),
                              ButtonSegment(
                                value: '5-8',
                                label: Text('Q5 – Q8'),
                              ),
                            ],
                            selected: {_activeTableType},
                            onSelectionChanged: (val) {
                              _switchTableType(val.first);
                            },
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Instruction note
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Non-numeric or empty marks are N/A (calculated as 0).',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // THE MARKS TABLE GRID (Exact rubric layout from user image)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black87, width: 1.5),
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Table Header: Marks (on) | [Col 1] | [Col 2] | [Col 3] | [Col 4]
                          Container(
                            color: const Color(0xFFD6D6D6), // Grey header
                            child: Row(
                              children: [
                                _buildTableHeadingCell('Marks (on)', flex: 2),
                                for (final q in _activeQuestions)
                                  _buildTableHeadingCell(q),
                              ],
                            ),
                          ),

                          // Rows a to f
                          for (final p in ['a', 'b', 'c', 'd', 'e', 'f'])
                            _buildDataRow(p),

                          // Row g with Grand Total cell on the right
                          _buildRowGWithGrandTotalHeader(),

                          // Total Row with Column totals & Grand Total value
                          _buildTotalRowWithGrandTotal(grandTotal),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom Bar with Grand Total pill and Verify Button
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 14.0,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Grand Total Live Display Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GRAND TOTAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text(
                          _formatNumber(grandTotal),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Verify & Submit Button
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submitVerification,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text(
                        'Verify & Submit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeadingCell(String title, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black87, width: 0.6),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String part) {
    return Row(
      children: [
        // Part label (a, b, c, etc.)
        Expanded(
          flex: 2,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87, width: 0.6),
              color: const Color(0xFFFAFAFA),
            ),
            alignment: Alignment.center,
            child: Text(
              part,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        // Cells for the 4 active questions
        for (final q in _activeQuestions) _buildEditableCell(q, part),
      ],
    );
  }

  Widget _buildRowGWithGrandTotalHeader() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87, width: 0.6),
              color: const Color(0xFFFAFAFA),
            ),
            alignment: Alignment.center,
            child: const Text(
              'g',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        for (final q in _activeQuestions) _buildEditableCell(q, 'g'),
        // Grand Total Label Header Cell
        Container(
          width: 58,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black87, width: 1.0),
            color: const Color(0xFFFEF3C7), // Light amber
          ),
          alignment: Alignment.center,
          child: const Text(
            'Grand\nTotal',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRowWithGrandTotal(double grandTotal) {
    return Row(
      children: [
        // 'Total' label
        Expanded(
          flex: 2,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87, width: 0.6),
              color: const Color(0xFFF1F5F9),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Total',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        // Live auto-calculated column totals for the 4 active questions
        for (final q in _activeQuestions)
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black87, width: 0.6),
                color: const Color(0xFFF1F5F9),
              ),
              alignment: Alignment.center,
              child: Text(
                _formatNumber(_calculateColTotal(q)),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: Colors.indigo,
                ),
              ),
            ),
          ),
        // Live Grand Total Value
        Container(
          width: 58,
          height: 42,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black87, width: 1.0),
            color: const Color(0xFFFDE68A), // Amber accent
          ),
          alignment: Alignment.center,
          child: Text(
            _formatNumber(grandTotal),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: Color(0xFFB45309), // Dark amber
            ),
          ),
        ),
      ],
    );
  }

  void _onCellEdited(String question, String part, String value) {
    final qInt = int.tryParse(question);
    if (qInt != null) {
      final mirroredQ = qInt <= 4 ? (qInt + 4).toString() : (qInt - 4).toString();
      final mirroredController = _controllers[mirroredQ]?[part];
      if (mirroredController != null && mirroredController.text != value) {
        mirroredController.text = value;
      }
    }
  }

  Widget _buildEditableCell(String question, String part) {
    final controller = _controllers[question]?[part];
    final currentText = controller?.text.trim() ?? '';
    final isNA = currentText.isEmpty || currentText.toUpperCase() == 'N/A';

    return Expanded(
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black87, width: 0.6),
        ),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) {
              final val = controller?.text.trim() ?? '';
              if (val.isEmpty || (val.toUpperCase() != 'N/A' && double.tryParse(val) == null)) {
                // If left empty or invalid, standardize to 'N/A'
                controller?.text = 'N/A';
                _onCellEdited(question, part, 'N/A');
                setState(() {});
              }
            }
          },
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isNA ? 11 : 13,
              fontWeight: isNA ? FontWeight.normal : FontWeight.w600,
              color: isNA ? Colors.grey.shade400 : const Color(0xFF1E3A8A),
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.indigo, width: 1.5),
              ),
            ),
            onChanged: (newVal) {
              _onCellEdited(question, part, newVal);
              setState(() {}); // Recalculates column totals and grand total live
            },
          ),
        ),
      ),
    );
  }
}
