import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/services/ocr_service.dart';
import '../../../../data/services/photo_store.dart';
import '../../../../domain/menu_logic/menu_line_parser.dart';
import '../../../../domain/menu_logic/menu_review_draft.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/photo.dart';
import '../../../../domain/models/price_entry.dart';
import 'menu_view_model.dart';

/// Steps of "Snap a menu": pick a photo, read it (OCR), review, save.
enum SnapPhase { choosePhoto, scanning, review, saving, saved }

class MenuSnapState {
  const MenuSnapState({
    this.phase = SnapPhase.choosePhoto,
    this.photoPath,
    this.draft = const MenuReviewDraft.empty(),
    this.hardToRead = false,
    this.reasons = const {},
    this.error,
    this.progress = 0,
    this.typedByHand = false,
  });

  final SnapPhase phase;

  /// Stored (relative) path of the photo, if one was taken.
  final String? photoPath;
  final MenuReviewDraft draft;

  /// Show "This one's hard to read. Typing it yourself will be more accurate."
  final bool hardToRead;
  final Set<HardToReadReason> reasons;
  final String? error;

  /// 0..1 while saving (progress write, motion).
  final double progress;

  /// The user chose to type the menu instead of scanning.
  final bool typedByHand;

  MenuSnapState copyWith({
    SnapPhase? phase,
    String? photoPath,
    bool clearPhoto = false,
    MenuReviewDraft? draft,
    bool? hardToRead,
    Set<HardToReadReason>? reasons,
    String? error,
    bool clearError = false,
    double? progress,
    bool? typedByHand,
  }) => MenuSnapState(
    phase: phase ?? this.phase,
    photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    draft: draft ?? this.draft,
    hardToRead: hardToRead ?? this.hardToRead,
    reasons: reasons ?? this.reasons,
    error: clearError ? null : (error ?? this.error),
    progress: progress ?? this.progress,
    typedByHand: typedByHand ?? this.typedByHand,
  );
}

/// View-model of the menu snap flow for one place.
class MenuSnapNotifier extends Notifier<MenuSnapState> {
  MenuSnapNotifier(this.placeId);

  final String placeId;

  String? _ocrText;
  String? _photoPath;
  var _saved = false;

  @override
  MenuSnapState build() {
    final store = ref.read(photoStoreProvider);
    // A photo that was never saved is not kept.
    ref.onDispose(() {
      final path = _photoPath;
      if (!_saved && path != null) store.deleteFile(path);
    });
    return const MenuSnapState();
  }

  /// Takes or picks a photo, then reads it on the device.
  Future<void> capture(ImageSource source) async {
    final store = ref.read(photoStoreProvider);
    final path = await store.pick(source, maxWidth: 2400);
    if (path == null || !ref.mounted) return;
    final old = state.photoPath;
    if (old != null) await store.deleteFile(old);
    _photoPath = path;
    state = state.copyWith(
      photoPath: path,
      phase: SnapPhase.scanning,
      clearError: true,
      typedByHand: false,
    );
    await _scan(path);
  }

  Future<void> _scan(String storedPath) async {
    try {
      final file = await ref.read(photoStoreProvider).resolve(storedPath);
      final result = await ref.read(ocrServiceProvider).recognize(file.path);
      if (!ref.mounted) return;
      _ocrText = result.text;
      final parsed = parseMenuLines(result.lines);
      state = state.copyWith(
        phase: SnapPhase.review,
        draft: MenuReviewDraft.fromParsed(parsed),
        hardToRead: parsed.isHardToRead,
        reasons: parsed.reasons,
      );
    } catch (_) {
      if (!ref.mounted) return;
      // OCR failed (model not available yet, corrupt image...): fall back to typing.
      state = state.copyWith(
        phase: SnapPhase.review,
        draft: _blankDraft(),
        hardToRead: true,
        reasons: const {HardToReadReason.noItems},
        error: "Couldn't read this photo.",
      );
    }
  }

  /// Type the menu by hand (the photo, if any, is still kept). With
  /// [discardScan] the lines read from the photo are dropped as well.
  void typeItYourself({bool discardScan = false}) {
    state = state.copyWith(
      phase: SnapPhase.review,
      draft: discardScan || state.draft.itemCount == 0
          ? _blankDraft()
          : state.draft,
      typedByHand: true,
      hardToRead: false,
      clearError: true,
    );
  }

  /// Back to the first step (retake the photo).
  void retake() => state = state.copyWith(
    phase: SnapPhase.choosePhoto,
    draft: const MenuReviewDraft.empty(),
    clearError: true,
  );

  MenuReviewDraft _blankDraft() {
    final withSection = const MenuReviewDraft.empty().addSection();
    return withSection.addItem(withSection.sections.single.id);
  }

  /// Applies an edit from the review screen.
  void edit(MenuReviewDraft Function(MenuReviewDraft) change) =>
      state = state.copyWith(draft: change(state.draft));

  /// Writes sections, items, option prices and the photo. Returns true on success.
  Future<bool> save() async {
    final draft = state.draft;
    if (!draft.canSave) return false;
    state = state.copyWith(phase: SnapPhase.saving, progress: 0);

    final menu = ref.read(menuRepositoryProvider);
    final prices = ref.read(pricesRepositoryProvider);
    final existingSections = await menu.watchSections(placeId).first;
    final existingItems = await menu.watchItems(placeId).first;
    final plan = buildMenuSavePlan(
      draft,
      placeId: placeId,
      existingSections: existingSections,
      existingSectionCount: existingSections.length,
      existingItemCount: existingItems.length,
    );

    final steps =
        plan.newSections.length + plan.items.length + plan.prices.length + 1;
    var done = 0;
    void tick() {
      done++;
      if (ref.mounted) state = state.copyWith(progress: done / steps);
    }

    for (final section in plan.newSections) {
      await menu.saveSection(section);
      tick();
    }
    for (final item in plan.items) {
      await menu.saveItem(item);
      tick();
    }
    final now = DateTime.now();
    for (final price in plan.prices) {
      await prices.save(
        PriceEntry(
          id: newId(),
          menuOptionId: price.menuOptionId,
          placeId: placeId,
          amount: price.amount,
          seenAt: now,
        ),
      );
      tick();
    }
    final photoPath = state.photoPath;
    if (photoPath != null) {
      await ref
          .read(photosRepositoryProvider)
          .save(
            Photo(
              id: newId(),
              ownerType: PhotoOwner.menu,
              ownerId: placeId,
              filePath: photoPath,
              ocrText: _ocrText,
            ),
          );
    }
    tick();
    _saved = true;
    ref.invalidate(menuLatestPricesProvider(placeId));
    if (ref.mounted) {
      state = state.copyWith(phase: SnapPhase.saved, progress: 1);
    }
    return true;
  }
}

final menuSnapProvider = NotifierProvider.autoDispose
    .family<MenuSnapNotifier, MenuSnapState, String>(MenuSnapNotifier.new);
