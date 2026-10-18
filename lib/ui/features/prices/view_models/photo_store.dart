import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../data/services/photo_store.dart' as shared;
import '../../../../domain/models/ids.dart';

/// What the price flow needs from photo storage. A thin adapter over the shared
/// `data/services/photo_store.dart` so every photo ends up as the same
/// relative `photos/<uuid>.jpg` path (DATA_MODEL § 1) that `StoredImage` reads.
abstract interface class PhotoStore {
  /// Copies a picked / captured file into the store and returns its stored path.
  Future<String> importFile(String sourcePath);

  /// Stores raw bytes (a downloaded product picture) and returns the stored path.
  Future<String> saveBytes(Uint8List bytes);
}

class SharedPhotoStore implements PhotoStore {
  SharedPhotoStore(this._shared);

  final shared.PhotoStore _shared;

  @override
  Future<String> importFile(String sourcePath) => _shared.import(sourcePath);

  @override
  Future<String> saveBytes(Uint8List bytes) async {
    final temp = await getTemporaryDirectory();
    final file = File('${temp.path}${Platform.pathSeparator}${newId()}.jpg');
    try {
      await file.writeAsBytes(bytes);
      return await _shared.import(file.path);
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }
}

final photoStoreProvider = Provider<PhotoStore>(
  (ref) => SharedPhotoStore(ref.watch(shared.photoStoreProvider)),
);

/// Where a photo comes from.
enum PhotoSource { camera, gallery }

/// Asks the user for a photo; returns the picked file's path or null when cancelled.
typedef PhotoPicker = Future<String?> Function(PhotoSource source);

Future<String?> _pickWithImagePicker(PhotoSource source) async {
  final file = await ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 85,
  );
  return file?.path;
}

/// Tests override this with a fake picker.
final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => _pickWithImagePicker,
);
