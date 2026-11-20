import 'dart:typed_data';

/// Storage abstraction so the upload/replace/delete workflow can be unit-tested.
abstract class PhotoStore {
  Future<void> upload(String path, Uint8List bytes, String contentType);

  /// true if an object was actually deleted. Storage answers 200 + [] when RLS
  /// filters the object out, so a blocked delete returns false instead of throwing.
  Future<bool> remove(String path);

  Future<String> signedUrl(String path, {int expiresInSeconds = 3600});
}

/// Thrown for problems with the photo itself. [message] is safe to show to users.
class PhotoException implements Exception {
  final String message;
  const PhotoException(this.message);

  @override
  String toString() => 'PhotoException: $message';
}

const maxPhotoBytes = 5 * 1024 * 1024; // same as the bucket's file_size_limit

class DetectedImage {
  final String extension;
  final String contentType;
  const DetectedImage(this.extension, this.contentType);
}

/// Detects by magic bytes, never by file name.
DetectedImage? detectImage(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return const DetectedImage('jpg', 'image/jpeg');
  }
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return const DetectedImage('png', 'image/png');
  }
  return null;
}

DetectedImage validatePhotoBytes(Uint8List b) {
  if (b.isEmpty) throw const PhotoException('The photo is empty.');
  if (b.length > maxPhotoBytes) throw const PhotoException('The photo is larger than 5 MB.');
  final img = detectImage(b);
  if (img == null) throw const PhotoException('Only JPEG or PNG photos are supported.');
  return img;
}
