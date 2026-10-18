import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show BitmapDescriptor;

import '../../../core/brand/dal_mark.dart';
import '../../../core/theme/daftar_typography.dart';
import 'map_markers.dart';

/// Draws [MarkerVisual]s into PNG bytes with a canvas (no widget tree, so it
/// works off-screen) and caches the result per picture, theme and pixel ratio.
class MarkerBitmaps {
  MarkerBitmaps();

  final _png = <String, Future<Uint8List>>{};
  final _descriptors = <String, BitmapDescriptor>{};

  /// A ready descriptor, or `null` while it is still being drawn (call [load]).
  BitmapDescriptor? peek(MarkerVisual v, MarkerPalette p, double ratio) =>
      _descriptors[_key(v, p, ratio)];

  /// Draws (once) and returns the descriptor.
  Future<BitmapDescriptor> load(
    MarkerVisual v,
    MarkerPalette p,
    double ratio,
  ) async {
    final key = _key(v, p, ratio);
    final bytes = await _png.putIfAbsent(key, () => renderPng(v, p, ratio));
    return _descriptors[key] ??= BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: ratio,
    );
  }

  static String _key(MarkerVisual v, MarkerPalette p, double ratio) =>
      '${v.cacheKey}|${p.key}|$ratio';

  /// PNG of [v] at [ratio] device pixels per logical pixel.
  static Future<Uint8List> renderPng(
    MarkerVisual v,
    MarkerPalette p,
    double ratio,
  ) async {
    final size = v.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(ratio);
    paintMarker(canvas, v, p);
    final image = await recorder.endRecording().toImage(
      (size.width * ratio).ceil(),
      (size.height * ratio).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Draws [v] in a `v.size` box at the origin.
  static void paintMarker(Canvas canvas, MarkerVisual v, MarkerPalette p) {
    switch (v) {
      case PricePinVisual():
        _price(canvas, v, p);
      case ClusterVisual():
        _cluster(canvas, v, p);
      case PlaceVisual():
        _place(canvas, v, p);
      case UserDotVisual():
        _user(canvas, v, p);
      case DropPinVisual():
        _drop(canvas, v, p);
    }
  }

  static void _text(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset center, {
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (maxWidth != null && tp.width > maxWidth) {
      final s = maxWidth / tp.width;
      canvas.scale(s);
    }
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    tp.dispose();
  }

  static void _price(Canvas canvas, PricePinVisual v, MarkerPalette p) {
    final style = pricePinStyle(v, p);
    const glow = PricePinVisual.glow;
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(glow, glow, v.size.width - 2 * glow, PricePinVisual.height),
      const Radius.circular(PricePinVisual.height / 2),
    );
    if (style.glow) {
      canvas.drawRRect(
        pill.inflate(glow),
        Paint()..color = p.lime.withValues(alpha: 0.35),
      );
    }
    canvas.drawRRect(pill, Paint()..color = style.fill);
    canvas.drawRRect(
      pill.deflate(style.borderWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.borderWidth
        ..color = style.border,
    );
    _text(
      canvas,
      v.pin.label,
      DaftarType.price(14, style.text).copyWith(letterSpacing: 0),
      pill.center,
      maxWidth: pill.width - 2 * pricePinPaddingX,
    );
  }

  static void _cluster(Canvas canvas, ClusterVisual v, MarkerPalette p) {
    final center = v.size.center(Offset.zero);
    const r = ClusterVisual.bubble / 2;
    if (v.hasBest) {
      canvas.drawCircle(
        center,
        r + 6,
        Paint()..color = p.lime.withValues(alpha: 0.35),
      );
    }
    canvas.drawCircle(center, r, Paint()..color = p.raised);
    final width = v.hasBest ? 2.0 : 1.0;
    canvas.drawCircle(
      center,
      r - width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = v.hasBest ? p.lime : p.line,
    );
    _text(
      canvas,
      '${v.count}',
      DaftarType.price(16, p.text).copyWith(letterSpacing: 0),
      center,
      maxWidth: ClusterVisual.bubble - 10,
    );
  }

  static void _place(Canvas canvas, PlaceVisual v, MarkerPalette p) {
    final center = v.size.center(Offset.zero);
    final r = (PlaceVisual.tile + (v.selected ? 6 : 0)) / 2;
    canvas.drawCircle(
      center.translate(0, 2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()..color = v.selected ? p.text : p.raised,
    );
    final width = v.selected ? 2.0 : 1.0;
    canvas.drawCircle(
      center,
      r - width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = v.selected ? p.background : p.line,
    );
    final icon = v.icon;
    _text(
      canvas,
      String.fromCharCode(icon.codePoint),
      TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 22,
        height: 1,
        color: v.selected ? p.background : p.text,
      ),
      center,
    );
  }

  static void _user(Canvas canvas, UserDotVisual v, MarkerPalette p) {
    final center = v.size.center(Offset.zero);
    canvas.drawCircle(
      center,
      UserDotVisual.dot / 2,
      Paint()..color = p.lime.withValues(alpha: 0.25),
    );
    canvas.drawCircle(center, 7, Paint()..color = p.text);
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = p.background,
    );
  }

  static void _drop(Canvas canvas, DropPinVisual v, MarkerPalette p) {
    const body = 40.0;
    final cx = v.size.width / 2;
    const tipHeight = 12.0;
    final center = Offset(cx, v.size.height - tipHeight - body / 2);
    // The pin's tip.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 2, v.size.height - tipHeight, 4, tipHeight),
        const Radius.circular(2),
      ),
      Paint()..color = p.lime,
    );
    canvas.drawCircle(center, body / 2, Paint()..color = p.lime);
    canvas.drawCircle(
      center,
      body / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = p.background,
    );
    canvas.save();
    canvas.translate(center.dx - 12, center.dy - 12);
    DalPainter(
      color: p.onLime,
      strokeWidth: 18,
    ).paint(canvas, const Size.square(24));
    canvas.restore();
  }
}
