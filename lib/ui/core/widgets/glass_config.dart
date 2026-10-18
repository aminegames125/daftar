import 'package:flutter/widgets.dart';

/// App-wide switch for the frosted blur on glass surfaces. `DaftarApp` places it
/// above the router and feeds it from the saved "Glass blur" setting, so low-end
/// phones can turn the blur off once instead of per widget.
///
/// [GlassSurface] reads it when its own `blur` argument is null.
class GlassConfig extends InheritedWidget {
  const GlassConfig({super.key, required this.blur, required super.child});

  final bool blur;

  /// Defaults to true when no [GlassConfig] is above [context].
  static bool blurOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassConfig>()?.blur ?? true;

  @override
  bool updateShouldNotify(GlassConfig old) => old.blur != blur;
}
