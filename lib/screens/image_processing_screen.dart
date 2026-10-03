import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';
import '../widgets/scanner_overlay.dart';
import 'verification_screen.dart';

class ImageProcessingScreen extends StatefulWidget {
  final String tableType;
  final Uint8List? imageBytes;

  const ImageProcessingScreen({
    super.key,
    this.tableType = '1-4',
    this.imageBytes,
  });

  @override
  State<ImageProcessingScreen> createState() => _ImageProcessingScreenState();
}

class _ImageProcessingScreenState extends State<ImageProcessingScreen> {
  static const _demoMarks = <String, Map<String, String>>{
    '1': {'a': '10', 'b': '13', 'c': '7', 'd': 'N/A', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '2': {'a': '8', 'b': '9', 'c': 'N/A', 'd': 'N/A', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '3': {'a': '12', 'b': '4', 'c': '6', 'd': '8', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '4': {'a': '9', 'b': '5', 'c': '7', 'd': 'N/A', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '5': {'a': '10', 'b': '13', 'c': '7', 'd': 'N/A', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '6': {'a': '8', 'b': '9', 'c': 'N/A', 'd': 'N/A', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '7': {'a': '12', 'b': '4', 'c': '6', 'd': '8', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
    '8': {'a': '9', 'b': '5', 'c': '7', 'd': 'N/A', 'e': 'N/A', 'f': 'N/A', 'g': 'N/A'},
  };

  late final MarksTableData _sampleData;
  String _status = 'Preparing sample preview...';
  double _progress = 0.12;
  bool _isPreviewing = true;

  @override
  void initState() {
    super.initState();
    final questions = widget.tableType == '1-4'
        ? MarksTableData.type1Questions
        : MarksTableData.type2Questions;
    _sampleData = MarksTableData(
      tableType: widget.tableType,
      questions: questions,
      cellMarks: {
        for (final question in questions)
          question: Map<String, String>.from(_demoMarks[question]!),
      },
    );
    _playPreview();
  }

  Future<void> _playPreview() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _status = 'Preparing image preview...';
      _progress = 0.62;
    });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() {
      _status = 'Image preview ready';
      _progress = 1;
      _isPreviewing = false;
    });
  }

  void _openVerification() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VerificationScreen(
          marksTableData: _sampleData,
          isSampleDemo: true,
          imageBytes: widget.imageBytes,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marksheet Preview'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                _isPreviewing
                    ? 'Previewing your selected image'
                    : 'Image preview ready',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Expanded(
                flex: 6,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ScannerOverlay(
                      isScanning: _isPreviewing,
                      scanColor: colorScheme.primary,
                      child: widget.imageBytes == null
                          ? Image.asset(
                              'assets/sample_marksheet.png',
                              fit: BoxFit.contain,
                            )
                          : Image.memory(
                              widget.imageBytes!,
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 10,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isPreviewing ? colorScheme.primary : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _status,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_isPreviewing)
                      const Text(
                        'Your image is previewed locally. Mark values remain sample data; OCR is disabled.',
                        textAlign: TextAlign.center,
                      )
                    else
                      FilledButton.icon(
                        onPressed: _openVerification,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review Marks'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
