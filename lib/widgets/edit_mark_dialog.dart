import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';

class EditMarkDialog extends StatefulWidget {
  final String question;
  final String part;
  final String value;
  final CellOcrResult result;
  const EditMarkDialog(
      {super.key,
      required this.question,
      required this.part,
      required this.value,
      required this.result});

  @override
  State<EditMarkDialog> createState() => _EditMarkDialogState();
}

class _EditMarkDialogState extends State<EditMarkDialog> {
  late final TextEditingController _controller;
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.value == 'N/A' ? '' : widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _crop() {
    try {
      final encoded = widget.result.cropBase64;
      if (encoded == null) return const Text('Crop preview unavailable');
      return Image.memory(base64Decode(encoded),
          height: 110,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('Crop preview unavailable'));
    } on FormatException {
      return const Text('Crop preview unavailable');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit Mark'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Question ${widget.question}, part ${widget.part}'),
                    const SizedBox(height: 8),
                    _crop(),
                    const SizedBox(height: 12),
                    Text(
                        'OCR text: ${widget.result.text.isEmpty ? '(empty)' : widget.result.text}'),
                    Text(
                        'Model confidence: ${(widget.result.confidence * 100).toStringAsFixed(1)}%'),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('edit-mark-input'),
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: 'Mark',
                          helperText: widget.result.maxMark == null
                              ? 'One or two digits'
                              : 'Maximum ${widget.result.maxMark}'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (!RegExp(r'^[0-9]{1,2}$').hasMatch(text)) {
                          return 'Enter one or two digits, or set N/A.';
                        }
                        if (widget.result.maxMark != null &&
                            int.parse(text) > widget.result.maxMark!) {
                          return 'Exceeds the maximum mark.';
                        }
                        return null;
                      },
                    ),
                  ],
                ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'N/A'),
              child: const Text('Set N/A')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, _controller.text.trim());
                }
              },
              child: const Text('Save')),
        ],
      );
}
