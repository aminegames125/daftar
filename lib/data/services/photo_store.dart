import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/ids.dart';

/// Photo files live in the app documents directory as `photos/<uuid>.jpg`; the
/// database stores that *relative* path (`photos` table, DATA_MODEL § 1).
abstract interface class PhotoStore {
  /// Opens the camera or gallery and stores the picked photo. Returns the
  /// relative path, or null when the user cancelled.
  Future<String?> pick(ImageSource source, {double maxWidth = 1600});

  /// Copies an existing file into `photos/` and returns the relative path.
  Future<String> import(String sourcePath);

  /// The file behind a stored path.
  Future<File> resolve(String storedPath);

  /// Deletes the file (the database row is the caller's job). Missing files are fine.
  Future<void> deleteFile(String storedPath);
}

class FilePhotoStore implements PhotoStore {
  FilePhotoStore({
    Future<Directory> Function()? documentsDir,
    ImagePicker? picker,
  }) : _documentsDir = documentsDir ?? getApplicationDocumentsDirectory,
       _picker = picker ?? ImagePicker();

  final Future<Directory> Function() _documentsDir;
  final ImagePicker _picker;

  static const folder = 'photos';

  @override
  Future<String?> pick(ImageSource source, {double maxWidth = 1600}) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        imageQuality: 85,
      );
    } on PlatformException {
      // No camera on this device, or the permission was refused: same as cancelling.
      return null;
    }
    if (picked == null) return null;
    return import(picked.path);
  }

  @override
  Future<String> import(String sourcePath) async {
    final root = await _documentsDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}$folder');
    await dir.create(recursive: true);
    final relative = '$folder/${newId()}.jpg';
    await File(sourcePath)
        .copy('${root.path}${Platform.pathSeparator}$relative');
    return relative;
  }

  @override
  Future<File> resolve(String storedPath) async {
    if (File(storedPath).isAbsolute) return File(storedPath);
    final root = await _documentsDir();
    return File('${root.path}${Platform.pathSeparator}$storedPath');
  }

  @override
  Future<void> deleteFile(String storedPath) async {
    final file = await resolve(storedPath);
    if (await file.exists()) await file.delete();
  }
}

final photoStoreProvider = Provider<PhotoStore>((ref) => FilePhotoStore());
