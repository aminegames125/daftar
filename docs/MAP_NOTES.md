# Map notes

The maps use `google_maps_flutter` (Android) instead of flutter_map/OSM, changed 2026-10-17.
This overrides the earlier "no Google Maps" decision (see D27 in PRODUCT.md).
Key setup: `docs/GOOGLE_MAPS_SETUP.md`.

## Structure

- `map_view.dart`: `MapView(MapViewConfig)`, `MapViewController` (animateTo / fit), marker + line specs,
  `mapViewBuilderProvider` (the swappable implementation).
- `google_map_view.dart`: the real `GoogleMap` (dark style, lite mode, marker bitmaps).
- `marker_bitmaps.dart` + `map_markers.dart`: marker pictures as data (`MarkerVisual`) drawn once to PNG and cached.
- `pin_layers.dart`: price pin / place markers with our own grid clustering (`pin_clustering.dart`, #107).
- `route_line_layer.dart`: `RouteDraw` animates the route line (#93).
- `place_drop_pin.dart`: drop pin marker; reveals with a fade (a bitmap marker cannot fall, #25).

## PriceMapView (reusable)

```dart
Expanded(child: PriceMapView(pins: pins, onPinTap: (pin) {...}))
```

- Input: `List<MapPin>`. Optional: `onPinTap`, `selectedPlaceId`, `bottomInset`, `showLocateButton`.
- Fills the space it is given. Fits the camera to the pins when the set changes.
- Shows Google's logo (lifted above the overlays through map padding) and the locate-me radar (#60).

## Tests

Widget tests never create the platform map. `test/ui/features/map/fake_map_view.dart` overrides
`mapViewBuilderProvider` with a placeholder that lists markers as labels; the default builder is also
an empty box under `FLUTTER_TEST`.
