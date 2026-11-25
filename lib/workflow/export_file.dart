import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportFile(BuildContext context, Uint8List bytes,
    {required String name,
    required String mimeType,
    required String title}) async {
  final file = XFile.fromData(bytes, mimeType: mimeType, name: name);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    final location = await FileSelectorPlatform.instance
        .getSaveLocation(options: SaveDialogOptions(suggestedName: name));
    if (location == null) return;
    await file.saveTo(location.path);
    return;
  }
  final box = context.findRenderObject() as RenderBox?;
  await Share.shareXFiles([file],
      fileNameOverrides: [name],
      subject: title,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size);
}
