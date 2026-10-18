import 'package:daftar/domain/models/map_pin.dart';
import 'package:daftar/ui/features/map/views/map_markers.dart';
import 'package:daftar/ui/features/map/views/marker_bitmaps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = MarkerPalette(
    raised: Color(0xFF181818),
    line: Color(0xFF333333),
    text: Color(0xFFF2F2F2),
    background: Color(0xFF000000),
    lime: Color(0xFFC6F432),
    onLime: Color(0xFF101010),
    amber: Color(0xFFFFB000),
  );
  const pin = MapPin(
    placeId: 'a',
    lat: 0,
    lng: 0,
    label: '3.200',
    isBest: true,
  );

  testWidgets('every marker visual draws a PNG', (tester) async {
    await tester.runAsync(() async {
      final visuals = <MarkerVisual>[
        const PricePinVisual(pin),
        const ClusterVisual(count: 12, hasBest: true),
        const PlaceVisual(icon: Icons.local_cafe, label: 'Cafe'),
        const PlaceVisual(
          icon: Icons.local_cafe,
          label: 'Cafe',
          selected: true,
        ),
        const UserDotVisual(),
        const DropPinVisual(),
      ];
      for (final v in visuals) {
        final bytes = await MarkerBitmaps.renderPng(v, palette, 2);
        expect(bytes.take(4).toList(), [
          0x89,
          0x50,
          0x4E,
          0x47,
        ], reason: v.cacheKey);
      }
    });
  });

  test('cache keys differ per picture', () {
    const other = MapPin(placeId: 'b', lat: 0, lng: 0, label: '3.200');
    expect(
      const PricePinVisual(pin).cacheKey,
      isNot(const PricePinVisual(other).cacheKey),
    );
    expect(
      const ClusterVisual(count: 2).cacheKey,
      isNot(const ClusterVisual(count: 3).cacheKey),
    );
  });

  test('drop pin touches the ground at its bottom centre', () {
    expect(const DropPinVisual().anchor, const Offset(0.5, 1));
  });
}
