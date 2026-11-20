import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

import 'photo_store.dart';

/// Camera/gallery picking. The picker downsizes and recompresses, so a normal
/// phone photo lands well under the 5 MB bucket limit.
class PhotoPickerService {
  final ImagePicker _picker;
  PhotoPickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// null = user cancelled. Throws [PhotoException] for unsupported/oversized photos.
  Future<Uint8List?> pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    validatePhotoBytes(bytes);
    return bytes;
  }
}
