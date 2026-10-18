import 'package:daftar/ui/features/map/views/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Lets widget tests run without the Google platform view: the real map is
/// replaced by this placeholder, which lists the markers as labelled boxes and
/// the lines as keyed boxes, and records camera calls.
///
/// ```dart
/// testApp(const MapScreen(), overrides: [fakeMapOverride()]);
/// ```
Override fakeMapOverride() => mapViewBuilderProvider.overrideWithValue(
  (context, config) => FakeMap(config),
);

/// The last config a [FakeMap] was built with (read the markers / lines / flags).
MapViewConfig? lastFakeMapConfig;

/// Camera calls received by fake maps, in order ('animateTo:lat,lng@zoom' / 'fit:n').
final fakeCameraCalls = <String>[];

class FakeMap extends StatefulWidget {
  const FakeMap(this.config, {super.key});

  final MapViewConfig config;

  @override
  State<FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<FakeMap> {
  @override
  void initState() {
    super.initState();
    widget.config.controller?.attach(
      animateTo: (target, zoom) async => fakeCameraCalls.add(
        'animateTo:${target.latitude},${target.longitude}@$zoom',
      ),
      fit: (points, maxZoom, padding) async =>
          fakeCameraCalls.add('fit:${points.length}'),
    );
  }

  @override
  void dispose() {
    widget.config.controller?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    lastFakeMapConfig = config;
    return ColoredBox(
      color: Colors.grey,
      // Below the screens' top overlays so taps reach the markers.
      child: Padding(
        padding: const EdgeInsets.only(top: 120),
        child: Wrap(
          children: [
            for (final line in config.lines)
              SizedBox(
                key: ValueKey('fake-line:${line.id}'),
                width: 1,
                height: 1,
              ),
            for (final m in config.markers)
              Opacity(
                opacity: m.alpha,
                child: GestureDetector(
                  key: ValueKey('fake-marker:${m.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: m.onTap,
                  child: Semantics(
                    button: true,
                    label: m.visual.semanticsLabel,
                    excludeSemantics: true,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: m.visual.text == null
                            ? null
                            : Text(m.visual.text!),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
