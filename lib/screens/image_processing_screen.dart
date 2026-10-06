import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';
import '../models/table_selection.dart';
import '../services/ocr_service.dart';
import '../widgets/scanner_overlay.dart';
import 'verification_screen.dart';

class ImageProcessingScreen extends StatefulWidget {
  final String? imagePath;
  final bool isSampleDemo;
  final String tableType;
  final BaseOcrService? ocrService;
  final bool autoNavigate;
  final TableSelection? selection;

  const ImageProcessingScreen({
    super.key,
    this.imagePath,
    this.isSampleDemo = false,
    this.tableType = '1-4',
    this.ocrService,
    this.autoNavigate = true,
    this.selection,
  });

  @override
  State<ImageProcessingScreen> createState() => _ImageProcessingScreenState();
}

class _ImageProcessingScreenState extends State<ImageProcessingScreen> {
  late final BaseOcrService _ocrService;

  String _currentStatus = 'Initializing Table OCR engine...';
  double _progress = 0.1;
  bool _isProcessing = true;
  bool _hasError = false;
  String _errorMessage = '';
  MarksTableData? _extractedData;

  @override
  void initState() {
    super.initState();
    _ocrService = widget.ocrService ??
        (!kIsWeb && Platform.isAndroid
            ? const LocalOcrService()
            : const PythonOcrService());
    _startOcrProcessing();
  }

  Future<void> _startOcrProcessing() async {
    setState(() {
      _isProcessing = true;
      _hasError = false;
      _progress = 0.1;
      _currentStatus = 'Initializing Table OCR engine...';
    });

    try {
      final data = await _ocrService.processImage(
        imagePath: widget.imagePath,
        tableType: widget.tableType,
        selection: widget.selection,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _currentStatus = status;
              _progress = progress;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _extractedData = data;
        _isProcessing = false;
      });

      if (widget.autoNavigate) {
        if (_ocrService is MockOcrService &&
            _ocrService.stepDuration == Duration.zero) {
          _navigateToVerification(data);
        } else {
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          _navigateToVerification(data);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _hasError = true;
        _errorMessage = 'Failed to process marks table: $e';
      });
    }
  }

  void _navigateToVerification(MarksTableData data) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VerificationScreen(
          marksTableData: data,
          imagePath: widget.imagePath,
          isSampleDemo: widget.isSampleDemo,
          imageRotation: widget.selection?.rotation ?? 0,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: curve,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0.0),
                end: Offset.zero,
              ).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  /// Builds preview of the captured image or a realistic visual replica of the marksheet rubric table
  Widget _buildTablePreview() {
    final hasLocalFile = !kIsWeb &&
        widget.imagePath != null &&
        File(widget.imagePath!).existsSync();

    if (hasLocalFile) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: RotatedBox(
          quarterTurns: (widget.selection?.rotation ?? 0) ~/ 90,
          child: Image(
            image: ResizeImage(FileImage(File(widget.imagePath!)),
                width: 2048, height: 2048, policy: ResizeImagePolicy.fit),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/sample_marksheet.png',
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning Marks Table'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 4),
              // Subtitle
              Text(
                _hasError
                    ? 'Could not read this marks table'
                    : _isProcessing
                        ? 'Extracting handwritten marks with OCR...'
                        : 'Table Marks Extracted Successfully!',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _isProcessing
                      ? colorScheme.onSurface
                      : Colors.green.shade700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Image Preview Container with Scanner Overlay
              Expanded(
                flex: _hasError ? 4 : 6,
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
                      isScanning: _isProcessing,
                      scanColor: colorScheme.primary,
                      child: _buildTablePreview(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Status and Progress Section
              Expanded(
                flex: _hasError ? 5 : 3,
                child: Center(
                    child: SingleChildScrollView(
                        child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_hasError) ...[
                      Icon(
                        Icons.error_outline_rounded,
                        color: colorScheme.error,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _startOcrProcessing,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry Scan'),
                      ),
                      if (widget.selection != null)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.crop),
                          label: const Text('Adjust Table Corners'),
                        ),
                    ] else ...[
                      // Animated Progress indicator
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: _progress),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, val, child) {
                          return Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: val,
                                  minHeight: 10,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _progress >= 1.0
                                        ? Colors.green
                                        : colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentStatus,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(val * 100).toInt()}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      if (!_isProcessing && _extractedData != null)
                        FilledButton.icon(
                          onPressed: () =>
                              _navigateToVerification(_extractedData!),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Review Extracted Marks'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Cancel & Rescan'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                    ],
                  ],
                ))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
