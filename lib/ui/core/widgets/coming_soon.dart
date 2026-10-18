import 'package:flutter/material.dart';

import '../brand/dal_mark.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';

/// Temporary empty state for screens not built yet. Delete each usage when the
/// real screen lands.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Chrome.contentBottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.headlineLarge),
            const Spacer(),
            Center(child: DalMark(size: 72, color: c.line)),
            const SizedBox(height: Space.lg),
            Center(
              child: Text(
                note,
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
