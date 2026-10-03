import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ocr_service.dart';
import 'image_processing_screen.dart';

class ImageSourceScreen extends StatefulWidget {
  final BaseOcrService? ocrService;

  const ImageSourceScreen({super.key, this.ocrService});

  @override
  State<ImageSourceScreen> createState() => _ImageSourceScreenState();
}

class _ImageSourceScreenState extends State<ImageSourceScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  String _selectedTableType = '1-4'; // '1-4' or '5-8'

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() => _isLoading = true);
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 92,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (pickedFile != null) {
        _navigateToProcessing(imagePath: pickedFile.path);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not access ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _navigateToProcessing({String? imagePath}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageProcessingScreen(
          imagePath: imagePath,
          tableType: _selectedTableType,
          ocrService: widget.ocrService,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curve,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.05),
                end: Offset.zero,
              ).animate(curve),
              child: child,
            ),
          );
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
        title: const Text(
          'MarkSheet OCR',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.3),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // Header Card
              Container(
                padding: const EdgeInsets.all(22.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22.0),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.table_chart_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Exam MarkSheet Scanner',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Detects handwritten marks from rubric tables. Non-numeric or blank marks are set to N/A and calculated as 0.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withOpacity(0.92),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Table Type Selector: Q1-Q4 vs Q5-Q8
              Text(
                'Select Rubric Table Type',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: '1-4',
                    label: Text('Questions 1, 2, 3, 4'),
                    icon: Icon(Icons.looks_one_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: '5-8',
                    label: Text('Questions 5, 6, 7, 8'),
                    icon: Icon(Icons.looks_5_rounded, size: 18),
                  ),
                ],
                selected: {_selectedTableType},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedTableType = newSelection.first;
                  });
                },
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Action Section Title
              Text(
                'Select Scan Method',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 14),

              // ONLY Button 1: Camera Action Button Card
              _ActionCard(
                icon: Icons.camera_alt_rounded,
                title: 'Capture Mark Sheet',
                subtitle: 'Photograph handwritten mark table with camera',
                buttonText: 'Open Camera',
                gradientColors: [
                  colorScheme.primaryContainer,
                  colorScheme.primaryContainer.withOpacity(0.7),
                ],
                iconColor: colorScheme.primary,
                isLoading: _isLoading,
                onTap: () => _pickImage(ImageSource.camera),
              ),

              const SizedBox(height: 16),

              // ONLY Button 2: Gallery Action Button Card
              _ActionCard(
                icon: Icons.photo_library_rounded,
                title: 'Upload Table Image',
                subtitle: 'Choose an existing marksheet photo from gallery',
                buttonText: 'Browse Gallery',
                gradientColors: [
                  colorScheme.surfaceContainerHighest,
                  colorScheme.surfaceContainerHighest.withOpacity(0.6),
                ],
                iconColor: colorScheme.onSurfaceVariant,
                isLoading: _isLoading,
                onTap: () => _pickImage(ImageSource.gallery),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final List<Color> gradientColors;
  final Color iconColor;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.gradientColors,
    required this.iconColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
