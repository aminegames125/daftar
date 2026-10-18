import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/core_routes.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/place_logic/place_draft.dart';
import '../../../core/motion/shake.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../map/views/map_markers.dart';
import '../../map/views/map_view.dart';
import '../../products/views/select_chip.dart';
import '../../settings/view_models/managed_lists.dart';
import '../view_models/place_form_view_model.dart';
import '../view_models/places_providers.dart';
import 'copy_chip.dart';
import 'location_picker_screen.dart';
import 'opening_hours_editor.dart';
import 'place_icons.dart';
import 'place_list_screen.dart';
import 'rating_stars.dart';
import 'stored_image.dart';

/// Add or edit a place. `placeId == null` adds a new one.
class PlaceFormScreen extends ConsumerStatefulWidget {
  const PlaceFormScreen({super.key, this.placeId, this.importText});

  final String? placeId;

  /// Text shared from Google Maps; fills the new place when the form opens.
  final String? importText;

  @override
  ConsumerState<PlaceFormScreen> createState() => _PlaceFormScreenState();
}

class _PlaceFormScreenState extends ConsumerState<PlaceFormScreen> {
  int _errorShake = 0;

  Future<void> _save() async {
    final form = ref.read(placeFormProvider(widget.placeId).notifier);
    final id = await form.save();
    if (!mounted) return;
    if (id == null) {
      setState(() => _errorShake++);
      unawaited(HapticFeedback.mediumImpact());
      return;
    }
    FloatingToast.show(
      context,
      widget.placeId == null ? 'Place added' : 'Place saved',
      kind: ToastKind.success,
    );
    if (widget.placeId == null) {
      context.pushReplacement(Routes.placeDetail(id));
    } else {
      context.pop();
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(placeFormProvider(widget.placeId));
    final isEdit = widget.placeId != null;

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.check_rounded,
          label: isEdit ? 'Save' : 'Add place',
          onTap: state.loading || state.saving ? null : _save,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: isEdit ? 'Edit place' : 'Add place',
            expandedHeight: 96,
            leading: HeaderIconButton(
              icon: Icons.close_rounded,
              label: 'Close',
              onTap: _close,
            ),
          ),
          if (state.loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Chrome.contentBottomPadding,
              ),
              sliver: SliverToBoxAdapter(
                child: _FormBody(
                  placeId: widget.placeId,
                  shakeTrigger: _errorShake,
                  importText: widget.importText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormBody extends ConsumerStatefulWidget {
  const _FormBody({
    required this.placeId,
    required this.shakeTrigger,
    this.importText,
  });

  final String? placeId;
  final String? importText;
  final int shakeTrigger;

  @override
  ConsumerState<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends ConsumerState<_FormBody> {
  late final PlaceFormNotifier _form = ref.read(
    placeFormProvider(widget.placeId).notifier,
  );
  late final _name = TextEditingController(
    text: ref.read(placeFormProvider(widget.placeId)).draft.name,
  );
  late final _address = TextEditingController(
    text: ref.read(placeFormProvider(widget.placeId)).draft.address,
  );
  late final _phone = TextEditingController(
    text: ref.read(placeFormProvider(widget.placeId)).draft.phone,
  );
  late final _wifiName = TextEditingController(
    text: ref.read(placeFormProvider(widget.placeId)).draft.wifiName,
  );
  late final _wifiPass = TextEditingController(
    text: ref.read(placeFormProvider(widget.placeId)).draft.wifiPassword,
  );
  late final _notes = TextEditingController(
    text: ref.read(placeFormProvider(widget.placeId)).draft.notes,
  );

  @override
  void initState() {
    super.initState();
    final text = widget.importText;
    if (text != null && text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _importText(text));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _wifiName, _wifiPass, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Reads the Google Maps link the user copied and pins the place from it.
  Future<void> _pullFromGoogleMaps() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    await _importText(clip?.text ?? '');
  }

  Future<void> _importText(String text) async {
    final place = await _form.importFromGoogleMaps(text);
    if (!mounted || place == null) return;
    final name = ref.read(placeFormProvider(widget.placeId)).draft.name;
    if (_name.text != name) _name.text = name;
    unawaited(HapticFeedback.mediumImpact());
  }

  Future<void> _openPicker() async {
    await Navigator.of(context)
        .push(LocationPickerScreen.route(widget.placeId));
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Sea view'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tag != null) _form.addTag(tag);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(placeFormProvider(widget.placeId));
    final draft = state.draft;
    final types = ref.watch(placeTypesProvider).value ?? const <PlaceType>[];
    final payments =
        ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final nameError =
        state.showErrors &&
        draft.validate().contains(PlaceDraftError.nameRequired);
    final selectedType = types.where((x) => x.id == draft.typeId).firstOrNull;

    // Keep the address box in step with changes made on the map screen.
    ref.listen(
      placeFormProvider(widget.placeId).select((s) => s.draft.address),
      (_, next) {
        if (_address.text != next) _address.text = next;
      },
    );

    final customTags = [
      for (final tag in draft.tags)
        if (!quickTags.contains(tag)) tag,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- name ---
        Shake(
          trigger: widget.shakeTrigger,
          child: TextField(
            controller: _name,
            autofocus: widget.placeId == null,
            textDirection: null,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: _form.setName,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: nameError ? 'Give the place a name' : null,
              errorBorder: OutlineInputBorder(
                borderRadius: Radii.inputR,
                borderSide: BorderSide(color: c.coral),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: Radii.inputR,
                borderSide: BorderSide(color: c.coral, width: 1.5),
              ),
            ),
          ),
        ),

        // --- type ---
        _SectionTitle(
          'Type',
          actionLabel: 'Manage',
          onAction: () =>
              context.push(SettingsRoutes.manage(ManagedListKind.placeTypes)),
        ),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final type in types)
              SelectChip(
                label: type.name,
                icon: placeTypeIcon(type.iconKey),
                selected: type.id == draft.typeId,
                onTap: () => _form.setType(type.id),
              ),
          ],
        ),
        if (selectedType != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              selectedType.kind == PlaceKind.shop
                  ? 'A shop: you log product prices here.'
                  : 'A venue: it gets a menu or price list.',
              style: t.bodySmall,
            ),
          ),

        // --- location ---
        const _SectionTitle('Location'),
        _LocationCard(
          lat: draft.lat,
          lng: draft.lng,
          locating: state.locating,
          onPick: _openPicker,
          onLocate: () async {
            await _form.useCurrentLocation();
          },
          onClear: draft.hasLocation ? _form.clearPosition : null,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: state.locating ? null : _pullFromGoogleMaps,
            icon: const Icon(Icons.content_paste_go_rounded, size: 18),
            label: const Text('Pull from Google Maps'),
          ),
        ),
        if (state.locationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              state.locationMessage!,
              style: t.bodySmall?.copyWith(color: c.amber),
            ),
          ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _address,
          textDirection: null,
          textInputAction: TextInputAction.next,
          onChanged: _form.setAddress,
          maxLines: null,
          decoration: const InputDecoration(labelText: 'Address (optional)'),
        ),
        if (draft.hasLocation)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _form.fillAddressFromPin,
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('Get the address from the pin'),
            ),
          ),

        // --- phone ---
        const _SectionTitle('Contact'),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onChanged: _form.setPhone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s().\-]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Phone (optional)',
            prefixIcon: Icon(Icons.call_outlined),
          ),
        ),

        // --- hours ---
        const _SectionTitle('Opening hours'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Set the weekly hours'),
          subtitle: const Text('Shows an "Open now" badge'),
          value: draft.openingHours != null,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            _form.enableHours(v);
          },
        ),
        if (draft.openingHours != null)
          OpeningHoursEditor(
            hours: draft.openingHours!,
            onDayChanged: _form.setDayRanges,
            onCopyToAll: _form.copyDayToAllDays,
          ),

        // --- wifi ---
        const _SectionTitle('Wi-Fi'),
        TextField(
          controller: _wifiName,
          textDirection: null,
          textInputAction: TextInputAction.next,
          onChanged: _form.setWifiName,
          decoration: const InputDecoration(
            labelText: 'Network name (optional)',
            prefixIcon: Icon(Icons.wifi_rounded),
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _wifiPass,
                textDirection: null,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _form.setWifiPassword,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
            ),
            if (draft.wifiPassword.isNotEmpty) ...[
              const SizedBox(width: Space.sm),
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: CopyChip(value: draft.wifiPassword, label: 'Copy'),
              ),
            ],
          ],
        ),

        // --- payments ---
        if (payments.isNotEmpty) ...[
          _SectionTitle(
            'Payment methods',
            actionLabel: 'Manage',
            onAction: () => context.push(
              SettingsRoutes.manage(ManagedListKind.paymentMethods),
            ),
          ),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final m in payments)
                SelectChip(
                  label: m.name,
                  icon: paymentIcon(m.iconKey),
                  selected: draft.paymentMethodIds.contains(m.id),
                  onTap: () => _form.togglePayment(m.id),
                ),
            ],
          ),
        ],

        // --- rating ---
        const _SectionTitle('Your rating'),
        RatingStars(rating: draft.rating, onChanged: _form.setRating),

        // --- tags ---
        const _SectionTitle('Quick tags'),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final tag in [...quickTags, ...customTags])
              SelectChip(
                label: tag,
                selected: draft.tags.contains(tag),
                onTap: () => _form.toggleTag(tag),
              ),
            SelectChip(
              label: '+ New',
              selected: false,
              isAdd: true,
              onTap: _addTag,
              semanticLabel: 'Add a tag',
            ),
          ],
        ),

        // --- notes ---
        const _SectionTitle('Notes'),
        TextField(
          controller: _notes,
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 8,
          onChanged: _form.setNotes,
          decoration: const InputDecoration(
            hintText: 'Anything worth remembering',
          ),
        ),

        // --- photos ---
        const _SectionTitle('Photos'),
        _PhotosStrip(
          photos: state.photos,
          onAdd: _form.addPhoto,
          onRemove: _form.removePhoto,
        ),

        if (widget.placeId != null) ...[
          const SizedBox(height: Space.xxxl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.coral,
              side: BorderSide(color: c.coral),
            ),
            onPressed: () async {
              final deleted = await confirmDeletePlace(
                context,
                ref,
                widget.placeId!,
                draft.name,
              );
              if (deleted && context.mounted) context.go(Routes.home);
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete place'),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xxl, bottom: Space.sm),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        if (onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel ?? 'Manage')),
      ],
    ),
  );
}

/// Mini map with the pin (tap to open the full picker) plus "I'm here".
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.lat,
    required this.lng,
    required this.locating,
    required this.onPick,
    required this.onLocate,
    this.onClear,
  });

  final double? lat;
  final double? lng;
  final bool locating;
  final VoidCallback onPick;
  final VoidCallback onLocate;
  final VoidCallback? onClear;

  static const _previewHeight = 148.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final has = lat != null && lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Squish(
          onTap: onPick,
          pressedScale: 0.99,
          child: Semantics(
            button: true,
            label: has
                ? 'Change location on the map'
                : 'Pick location on the map',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: Radii.cardR,
              child: SizedBox(
                height: _previewHeight,
                child: has
                    ? MapView(
                        key: ValueKey('$lat,$lng'),
                        MapViewConfig(
                          initialTarget: LatLng(lat!, lng!),
                          initialZoom: 16,
                          // A static lite map: cheap, and no live map per form.
                          lite: true,
                          interactive: false,
                          markers: [
                            MapMarkerSpec(
                              id: 'preview',
                              position: LatLng(lat!, lng!),
                              visual: const DropPinVisual(),
                            ),
                          ],
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.raised,
                          borderRadius: Radii.cardR,
                          border: Border.all(color: c.line),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(Space.sm),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add_location_alt_outlined,
                                    color: c.muted,
                                  ),
                                  const SizedBox(height: Space.sm),
                                  Text('No location yet', style: t.bodySmall),
                                  Text(
                                    'Optional, e.g. for online shops',
                                    style: t.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: locating ? null : onLocate,
                icon: locating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: const Text("I'm here"),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(has ? 'Move pin' : 'Pick on map'),
              ),
            ),
          ],
        ),
        if (onClear != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onClear,
              child: Text('Remove location', style: TextStyle(color: c.muted)),
            ),
          ),
      ],
    );
  }
}

class _PhotosStrip extends StatelessWidget {
  const _PhotosStrip({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<FormPhoto> photos;
  final ValueChanged<ImageSource> onAdd;
  final ValueChanged<String> onRemove;

  static const _size = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: _size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in photos)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: Radii.inputR,
                    child: SizedBox.square(
                      dimension: _size,
                      child: StoredImage(path: p.path, cacheWidth: 288),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Semantics(
                      button: true,
                      label: 'Remove photo',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onRemove(p.id),
                        child: SizedBox.square(
                          dimension: Chrome.minTouch,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              margin: const EdgeInsets.all(Space.xs),
                              padding: const EdgeInsets.all(Space.xs),
                              decoration: BoxDecoration(
                                color: c.background.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: c.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _AddPhotoTile(
            icon: Icons.photo_camera_outlined,
            label: 'Camera',
            onTap: () => onAdd(ImageSource.camera),
          ),
          const SizedBox(width: Space.sm),
          _AddPhotoTile(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            onTap: () => onAdd(ImageSource.gallery),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Squish(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Add photo from $label',
        excludeSemantics: true,
        child: Container(
          width: _PhotosStrip._size,
          height: _PhotosStrip._size,
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: Radii.inputR,
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: c.text),
                  const SizedBox(height: Space.xs),
                  Text(label, style: t.labelMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
