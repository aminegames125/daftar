import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/photo_store.dart';
import '../../../core/theme/daftar_colors.dart';

/// Shows a photo by its stored path (`photos/<uuid>.jpg`, resolved against the
/// app documents directory). Falls back to a quiet placeholder if the file is gone.
class StoredImage extends ConsumerStatefulWidget {
  const StoredImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  ConsumerState<StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends ConsumerState<StoredImage> {
  late Future<File> _file = ref.read(photoStoreProvider).resolve(widget.path);

  @override
  void didUpdateWidget(StoredImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _file = ref.read(photoStoreProvider).resolve(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = ColoredBox(
      color: c.raised,
      child: Icon(Icons.image_outlined, color: c.muted),
    );
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return placeholder;
        return Image.file(
          file,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
        );
      },
    );
  }
}
