import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/table_selection.dart';
import '../services/ocr_service.dart';
import '../widgets/table_crop_overlay.dart';
import 'image_processing_screen.dart';

class TableCropScreen extends StatefulWidget {
  final String imagePath;
  final String tableType;
  final BaseOcrService? ocrService;

  const TableCropScreen(
      {super.key,
      required this.imagePath,
      this.tableType = '1-4',
      this.ocrService});

  @override
  State<TableCropScreen> createState() => _TableCropScreenState();
}

class _TableCropScreenState extends State<TableCropScreen> {
  late final BaseOcrService _service;
  ImageProvider? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;
  String? _loadError;
  TableSelection _selection = TableSelection.initial();
  TableSelection _resetSelection = TableSelection.initial();
  String _status = 'Preparing photograph…';
  bool _detecting = false;
  bool _continuing = false;
  int _revision = 0;
  int _detectionId = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.ocrService ??
        (!kIsWeb && Platform.isAndroid
            ? const LocalOcrService()
            : const PythonOcrService());
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('Select an image smaller than 10 MB.');
      }
      if (!mounted) return;
      _image = ResizeImage(FileImage(file),
          width: 2048, height: 2048, policy: ResizeImagePolicy.fit);
      _stream = _image!.resolve(ImageConfiguration.empty);
      _listener = ImageStreamListener((info, _) {
        final size =
            Size(info.image.width.toDouble(), info.image.height.toDouble());
        info.dispose();
        if (!mounted || _imageSize != null) return;
        setState(() {
          _imageSize = size;
          _status = 'Align the four corners with the main table.';
        });
        _detect();
      }, onError: (Object error, StackTrace? stack) {
        if (mounted) {
          setState(() => _loadError =
              'This photograph could not be opened. Choose another image.');
        }
      });
      _stream!.addListener(_listener!);
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = 'Could not open the photograph: $error');
      }
    }
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  Future<void> _detect() async {
    final service = _service;
    if (service is! TableDetectionService) return;
    final revision = _revision;
    final id = ++_detectionId;
    setState(() {
      _detecting = true;
      _status = 'Finding the table… You can also adjust the corners now.';
    });
    try {
      final detected = await (service as TableDetectionService).detectTable(
          imagePath: widget.imagePath, rotation: _selection.rotation);
      if (!mounted || id != _detectionId || revision != _revision) return;
      setState(() {
        if (detected != null) {
          _selection = detected;
          _resetSelection = detected;
          _status = 'Table found. Check the corners, then continue.';
        } else {
          _status =
              'We couldn’t locate the table automatically. Adjust the four corners and continue.';
        }
      });
    } catch (_) {
      if (!mounted || id != _detectionId || revision != _revision) return;
      setState(() => _status =
          'Automatic detection is unavailable. Adjust the four corners and continue.');
    } finally {
      if (mounted && id == _detectionId) setState(() => _detecting = false);
    }
  }

  void _change(TableSelection selection) {
    if (_continuing || !selection.isValid) return;
    setState(() {
      _revision++;
      _selection = selection;
      _status =
          'Check that the table is upright and all seven rows are inside.';
    });
  }

  Future<void> _continue() async {
    if (_continuing || _imageSize == null || !_selection.isValid) return;
    setState(() {
      _continuing = true;
      _revision++; // A late detection must never overwrite an accepted crop.
    });
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ImageProcessingScreen(
            imagePath: widget.imagePath,
            tableType: widget.tableType,
            ocrService: _service,
            selection: _selection)));
    if (mounted) setState(() => _continuing = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _imageSize != null && !_continuing && _loadError == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust Table'), actions: [
        if (_service is TableDetectionService)
          IconButton(
            tooltip: 'Auto-detect table',
            onPressed: ready && !_detecting ? _detect : null,
            icon: const Icon(Icons.auto_fix_high),
          ),
      ]),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        // Scroll on short/landscape windows while keeping usable drag handles.
        return SingleChildScrollView(
            child: SizedBox(
          height: constraints.maxHeight.clamp(
              600.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
              double.infinity),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Questions ${widget.tableType.replaceAll('-', '–')}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                      'Keep the header, rows a–g and total row inside the corners. Exclude the small Grand Total extension.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Expanded(
                      child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        color: const Color(0xFF172334),
                        borderRadius: BorderRadius.circular(20)),
                    child: _loadError != null
                        ? Center(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(_loadError!,
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center)))
                        : _imageSize == null
                            ? const Center(child: CircularProgressIndicator())
                            : TableCropOverlay(
                                image: _image!,
                                imageSize: _imageSize!,
                                selection: _selection,
                                onCornerMoved: (index, delta) => _change(
                                    _selection.moveCorner(index,
                                        _selection.corners[index] + delta))),
                  )),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (_detecting) ...[
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                        child: Text(_status,
                            key: const ValueKey('crop-status'),
                            style: Theme.of(context).textTheme.bodySmall)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                    TextButton.icon(
                        onPressed: ready
                            ? () => _change(_selection.rotateCounterclockwise())
                            : null,
                        icon: const Icon(Icons.rotate_left),
                        label: const Text('Rotate Left')),
                    TextButton.icon(
                        onPressed: ready
                            ? () => _change(_selection.rotateClockwise())
                            : null,
                        icon: const Icon(Icons.rotate_right),
                        label: const Text('Rotate Right')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    OutlinedButton.icon(
                        onPressed:
                            ready ? () => _change(_resetSelection) : null,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset')),
                    const Spacer(),
                    FilledButton.icon(
                        key: const ValueKey('crop-continue'),
                        onPressed: ready ? _continue : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue')),
                  ]),
                ]),
          ),
        ));
      })),
    );
  }
}
