import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/router.dart';
import '../../../core/brand/dal_mark.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/success_check.dart';
import '../../places/view_models/places_providers.dart';
import '../../places/views/place_row.dart';
import '../../places/views/stored_image.dart';
import '../view_models/menu_snap_view_model.dart';
import 'menu_review_view.dart';
import 'menu_scan_overlay.dart';

/// Snap a menu (`Routes.menuSnap`): photo, on-device text reading, review, save.
/// With no `?placeId=` it first asks which place the menu belongs to.
class MenuSnapScreen extends ConsumerStatefulWidget {
  const MenuSnapScreen({super.key, this.placeId});

  final String? placeId;

  @override
  ConsumerState<MenuSnapScreen> createState() => _MenuSnapScreenState();
}

class _MenuSnapScreenState extends ConsumerState<MenuSnapScreen> {
  String? _placeId;

  @override
  void initState() {
    super.initState();
    _placeId = widget.placeId;
  }

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final placeId = _placeId;
    if (placeId == null) {
      return _PlacePicker(
        onPicked: (id) => setState(() => _placeId = id),
        onBack: _back,
      );
    }
    return _SnapFlow(
      placeId: placeId,
      onBack: _back,
      onChangePlace: widget.placeId == null
          ? () => setState(() => _placeId = null)
          : null,
    );
  }
}

class _PlacePicker extends ConsumerWidget {
  const _PlacePicker({required this.onPicked, required this.onBack});

  final ValueChanged<String> onPicked;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(placeEntriesProvider);
    return Scaffold(
      extendBody: true,
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: 'Snap a menu',
            subtitle: 'Which place is it from?',
            expandedHeight: 120,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: onBack,
            ),
          ),
          entries.when(
            loading: () => const SliverToBoxAdapter(
              child: SkeletonList(padding: EdgeInsets.all(Space.gutter)),
            ),
            error: (_, _) => const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(message: "Couldn't load your places."),
            ),
            data: (list) {
              if (list.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyState(
                      message: 'Add the place first, then snap its menu.',
                      actionLabel: 'Add place',
                      onAction: () => context.push(Routes.placeNew),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Chrome.contentBottomPadding,
                ),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => PlaceRow(
                    entry: list[i],
                    onTap: () => onPicked(list[i].place.id),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SnapFlow extends ConsumerWidget {
  const _SnapFlow({
    required this.placeId,
    required this.onBack,
    this.onChangePlace,
  });

  final String placeId;
  final VoidCallback onBack;
  final VoidCallback? onChangePlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(menuSnapProvider(placeId));
    final snap = ref.read(menuSnapProvider(placeId).notifier);
    final place = ref.watch(placeProvider(placeId)).value;
    final itemCount = state.draft.itemCount;

    Widget? toolbar;
    if (state.phase == SnapPhase.review) {
      toolbar = DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.photo_camera_outlined,
            label: 'Retake photo',
            onTap: snap.retake,
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.check_rounded,
          label: itemCount == 1 ? 'Save 1 item' : 'Save $itemCount items',
          onTap: state.draft.canSave ? () => snap.save() : null,
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: toolbar,
      body: switch (state.phase) {
        SnapPhase.choosePhoto => _Header(
          title: 'Snap a menu',
          subtitle: place?.name,
          onBack: onBack,
          child: _ChoosePhoto(snap: snap, onChangePlace: onChangePlace),
        ),
        SnapPhase.scanning => _Header(
          title: 'Reading the menu',
          subtitle: place?.name,
          onBack: onBack,
          child: _Scanning(photoPath: state.photoPath),
        ),
        SnapPhase.review => _Header(
          title: 'Check the menu',
          subtitle: place?.name,
          onBack: onBack,
          child: _Review(state: state, snap: snap),
        ),
        SnapPhase.saving => _Saving(progress: state.progress),
        SnapPhase.saved => Center(
          child: SuccessCheck(
            onDone: () {
              FloatingToast.show(
                context,
                'Menu saved',
                subtitle: itemCount == 1 ? '1 item' : '$itemCount items',
                kind: ToastKind.success,
              );
              onBack();
            },
          ),
        ),
      },
    );
  }
}

/// Shared scaffold body: collapsing header + padded content.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onBack,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        CollapsingHeader(
          title: title,
          subtitle: subtitle,
          expandedHeight: 110,
          leading: HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onTap: onBack,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            Chrome.contentBottomPadding,
          ),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class _ChoosePhoto extends StatelessWidget {
  const _ChoosePhoto({required this.snap, this.onChangePlace});

  final MenuSnapNotifier snap;
  final VoidCallback? onChangePlace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.symmetric(vertical: Space.xl),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: Radii.cardR,
            border: Border.all(color: c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.document_scanner_outlined, size: 48, color: c.muted),
              const SizedBox(height: Space.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: Text(
                  'Take a clear, straight photo of the menu. Daftar reads it on your phone, then you check it.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        FilledButton.icon(
          onPressed: () => snap.capture(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Take a photo'),
        ),
        const SizedBox(height: Space.md),
        OutlinedButton.icon(
          onPressed: () => snap.capture(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from gallery'),
        ),
        const SizedBox(height: Space.md),
        TextButton(
          onPressed: snap.typeItYourself,
          child: const Text('Type it myself'),
        ),
        if (onChangePlace != null)
          TextButton(
            onPressed: onChangePlace,
            child: const Text('Change place'),
          ),
        const SizedBox(height: Space.sm),
        Text(
          'Arabic menus are hard for the phone to read. For those, typing is more accurate.',
          textAlign: TextAlign.center,
          style: t.bodySmall,
        ),
      ],
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({required this.photoPath});

  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        ClipRRect(
          borderRadius: Radii.cardR,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photoPath != null) StoredImage(path: photoPath!),
                const MenuScanOverlay(),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Text('Reading the lines…', style: t.bodyMedium),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.state, required this.snap});

  final MenuSnapState state;
  final MenuSnapNotifier snap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.hardToRead) ...[
          HardToReadBanner(
            onRetake: snap.retake,
            onTypeIt: () => snap.typeItYourself(discardScan: true),
          ),
          const SizedBox(height: Space.lg),
        ],
        if (state.photoPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: Radii.inputR,
                  child: SizedBox.square(
                    dimension: 64,
                    child: StoredImage(path: state.photoPath!, cacheWidth: 192),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'The photo is kept with this place.',
                    style: t.bodySmall?.copyWith(color: c.muted),
                  ),
                ),
              ],
            ),
          ),
        if (!state.hardToRead &&
            !state.typedByHand &&
            state.draft.itemCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Text(
              'Fix anything the phone got wrong, then save.',
              style: t.bodyMedium,
            ),
          ),
        MenuReviewView(draft: state.draft, onEdit: snap.edit),
      ],
    );
  }
}

/// Progress write: the Dal draws itself as the menu is saved.
class _Saving extends StatelessWidget {
  const _Saving({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final pct = (progress * 100).round();
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Saving the menu, $pct percent',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                DalMark(size: 96, color: c.line),
                DalMark(size: 96, progress: progress),
              ],
            ),
            const SizedBox(height: Space.lg),
            Text('Saving the menu… $pct%', style: t.bodyMedium),
          ],
        ),
      ),
    );
  }
}
