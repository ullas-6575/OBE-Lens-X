import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// image_picker returns a browser blob URL on web and a filesystem path on
// native platforms. Keep both previews in the original image coordinate frame.
bool selectedImageExists(String? path) =>
    path != null && (kIsWeb || File(path).existsSync());

ImageProvider selectedImageProvider(String path) =>
    kIsWeb ? NetworkImage(path) : FileImage(File(path)) as ImageProvider;
