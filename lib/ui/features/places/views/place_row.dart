import 'package:flutter/material.dart';

import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../view_models/places_providers.dart';
import 'open_status_badge.dart';
import 'place_icons.dart';

/// A place in a list: type icon tile, name, "Type · address", open status, rating.
class PlaceRow extends StatelessWidget {
  const PlaceRow({super.key, required this.entry, this.onTap, this.trailing});

  final PlaceEntry entry;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final place = entry.place;
    final address = place.address;
    final meta = [
      entry.type.name,
      if (address != null && address.isNotEmpty) address,
    ].join(' · ');

    return Squish(
      onTap: onTap,
      pressedScale: 0.98,
      child: Semantics(
        button: onTap != null,
        container: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    placeTypeIcon(entry.type.iconKey),
                    size: 22,
                    color: c.text,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium,
                      ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall,
                      ),
                      if (place.openingHours != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: OpenStatusBadge(hours: place.openingHours),
                        ),
                    ],
                  ),
                ),
                if (place.rating != null) ...[
                  const SizedBox(width: Space.md),
                  Icon(Icons.star_rounded, size: 16, color: c.text),
                  const SizedBox(width: 2),
                  Text('${place.rating}', style: t.labelMedium),
                ],
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
