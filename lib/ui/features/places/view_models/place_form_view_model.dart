import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/services/geocoding_location.dart';
import '../../../../data/services/nominatim_client.dart';
import '../../../../data/services/photo_store.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/photo.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/place_logic/google_maps_link.dart';
import '../../../../domain/place_logic/opening_hours_edit.dart';
import '../../../../domain/place_logic/place_draft.dart';

/// A photo shown on the form. [isNew] ones are files not yet linked to the place.
class FormPhoto {
  const FormPhoto({required this.id, required this.path, required this.isNew});

  final String id;
  final String path;
  final bool isNew;
}

class PlaceFormState {
  const PlaceFormState({
    required this.draft,
    this.isEdit = false,
    this.loading = false,
    this.saving = false,
    this.showErrors = false,
    this.photos = const [],
    this.locating = false,
    this.locationMessage,
    this.savedId,
  });

  final PlaceDraft draft;
  final bool isEdit;
  final bool loading;
  final bool saving;

  /// True after a failed save attempt, so required fields turn red.
  final bool showErrors;
  final List<FormPhoto> photos;
  final bool locating;

  /// Shown under the map when GPS or address search could not help.
  final String? locationMessage;

  /// Set once the place is stored; the screen then closes.
  final String? savedId;

  PlaceFormState copyWith({
    PlaceDraft? draft,
    bool? loading,
    bool? saving,
    bool? showErrors,
    List<FormPhoto>? photos,
    bool? locating,
    String? locationMessage,
    bool clearMessage = false,
    String? savedId,
  }) => PlaceFormState(
    draft: draft ?? this.draft,
    isEdit: isEdit,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    showErrors: showErrors ?? this.showErrors,
    photos: photos ?? this.photos,
    locating: locating ?? this.locating,
    locationMessage: clearMessage
        ? null
        : (locationMessage ?? this.locationMessage),
    savedId: savedId ?? this.savedId,
  );
}

/// State of the add / edit place screen. `placeId == null` means a new place.
class PlaceFormNotifier extends Notifier<PlaceFormState> {
  PlaceFormNotifier(this.placeId);

  final String? placeId;

  final _removedPhotoIds = <String>{};
  final _newPhotoPaths = <String>{};
  var _saved = false;

  @override
  PlaceFormState build() {
    final store = ref.read(photoStoreProvider);
    // Photos taken but never saved are deleted when the form closes.
    ref.onDispose(() {
      if (_saved) return;
      for (final path in _newPhotoPaths) {
        store.deleteFile(path);
      }
    });
    _load();
    return PlaceFormState(
      draft: PlaceDraft(id: placeId ?? newId()),
      isEdit: placeId != null,
      loading: true,
    );
  }

  Future<void> _load() async {
    final id = placeId;
    if (id != null) {
      final place = await ref.read(placesRepositoryProvider).get(id);
      final photos = await ref
          .read(photosRepositoryProvider)
          .watchFor(PhotoOwner.place, id)
          .first;
      if (!ref.mounted) return;
      state = state.copyWith(
        draft: place == null ? state.draft : PlaceDraft.fromPlace(place),
        photos: [
          for (final p in photos)
            FormPhoto(id: p.id, path: p.filePath, isNew: false),
        ],
        loading: false,
      );
      return;
    }
    // New place: start with the first place type so the form is valid after typing a name.
    final types = await ref.read(placeTypesRepositoryProvider).watchAll().first;
    if (!ref.mounted) return;
    state = state.copyWith(
      draft: state.draft.typeId == null && types.isNotEmpty
          ? state.draft.copyWith(typeId: types.first.id)
          : null,
      loading: false,
    );
  }

  void _update(PlaceDraft draft) => state = state.copyWith(draft: draft);

  void setName(String v) => _update(state.draft.copyWith(name: v));
  void setType(String typeId) => _update(state.draft.copyWith(typeId: typeId));
  void setAddress(String v) => _update(state.draft.copyWith(address: v));
  void setPhone(String v) => _update(state.draft.copyWith(phone: v));
  void setWifiName(String v) => _update(state.draft.copyWith(wifiName: v));
  void setWifiPassword(String v) =>
      _update(state.draft.copyWith(wifiPassword: v));
  void setNotes(String v) => _update(state.draft.copyWith(notes: v));

  void setRating(int? rating) => _update(
    rating == null
        ? state.draft.copyWith(clearRating: true)
        : state.draft.copyWith(rating: rating),
  );

  void togglePayment(String methodId) {
    final ids = {...state.draft.paymentMethodIds};
    if (!ids.remove(methodId)) ids.add(methodId);
    _update(state.draft.copyWith(paymentMethodIds: ids));
  }

  void toggleTag(String tag) {
    final tags = [...state.draft.tags];
    if (!tags.remove(tag)) tags.add(tag);
    _update(state.draft.copyWith(tags: tags));
  }

  void addTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty || state.draft.tags.contains(t)) return;
    _update(state.draft.copyWith(tags: [...state.draft.tags, t]));
  }

  // ---- location ----

  /// Drop or move the pin. Pass an address to fill the field at the same time.
  void setPosition(double lat, double lng, {String? address}) {
    state = state.copyWith(
      draft: state.draft.copyWith(lat: lat, lng: lng, address: address),
      clearMessage: true,
    );
  }

  void clearPosition() =>
      state = state.copyWith(draft: state.draft.copyWith(clearLocation: true));

  /// GPS "I'm here" (D23). Returns the fix so the map can fly to it.
  Future<LocationFix> useCurrentLocation() async {
    state = state.copyWith(locating: true, clearMessage: true);
    final fix = await ref.read(locationServiceProvider).currentPosition();
    if (!ref.mounted) return fix;
    if (fix.isOk) {
      state = state.copyWith(
        draft: state.draft.copyWith(lat: fix.lat, lng: fix.lng),
        locating: false,
      );
    } else {
      state = state.copyWith(
        locating: false,
        locationMessage: locationFailureText(fix.status),
      );
    }
    return fix;
  }

  /// "Uno reverse": takes what Google Maps shared (a link, share text or
  /// "lat, lng"), drops the pin there and fills the name when it is still empty.
  /// Returns the place that was read, or null (a message is shown) when nothing
  /// usable was found.
  Future<GoogleMapsPlace?> importFromGoogleMaps(String text) async {
    state = state.copyWith(locating: true, clearMessage: true);
    final place = await ref.read(googleMapsImporterProvider).import(text);
    if (!ref.mounted) return place;
    if (place == null || !place.hasPosition) {
      state = state.copyWith(
        locating: false,
        locationMessage: 'No Google Maps place found. In Google Maps tap Share, copy the link, then try again.',
      );
      return null;
    }
    final d = state.draft;
    state = state.copyWith(
      draft: d.copyWith(
        lat: place.lat,
        lng: place.lng,
        name: d.name.trim().isEmpty ? place.name : null,
      ),
      locating: false,
    );
    return place;
  }

  /// Fills the address field from the pin using Nominatim. Fails softly offline.
  Future<void> fillAddressFromPin() async {
    final d = state.draft;
    if (!d.hasLocation) return;
    try {
      final address = await ref
          .read(nominatimClientProvider)
          .reverse(d.lat!, d.lng!);
      if (!ref.mounted) return;
      if (address != null) _update(state.draft.copyWith(address: address));
    } on NominatimException {
      if (ref.mounted) {
        state = state.copyWith(
          locationMessage: "Can't look up the address right now.",
        );
      }
    }
  }

  // ---- hours ----

  void enableHours(bool enabled) => _update(
    enabled
        ? state.draft.copyWith(openingHours: defaultOpeningHours())
        : state.draft.copyWith(clearHours: true),
  );

  void setDayRanges(String day, List<TimeRange> ranges) => _update(
    state.draft.copyWith(
      openingHours: setDay(state.draft.openingHours, day, ranges),
    ),
  );

  void copyDayToAllDays(String day) {
    final hours = state.draft.openingHours;
    if (hours != null) {
      _update(state.draft.copyWith(openingHours: copyDayToAll(hours, day)));
    }
  }

  // ---- photos ----

  Future<void> addPhoto(ImageSource source) async {
    final path = await ref.read(photoStoreProvider).pick(source);
    if (path == null) return;
    _newPhotoPaths.add(path);
    if (!ref.mounted) return;
    state = state.copyWith(
      photos: [
        ...state.photos,
        FormPhoto(id: newId(), path: path, isNew: true),
      ],
    );
  }

  Future<void> removePhoto(String photoId) async {
    final photo = state.photos.where((p) => p.id == photoId).firstOrNull;
    if (photo == null) return;
    state = state.copyWith(
      photos: state.photos.where((p) => p.id != photoId).toList(),
    );
    if (photo.isNew) {
      _newPhotoPaths.remove(photo.path);
      await ref.read(photoStoreProvider).deleteFile(photo.path);
    } else {
      _removedPhotoIds.add(photo.id); // deleted on save
    }
  }

  // ---- save ----

  /// Saves the place and its photos. Returns the place id, or null when the
  /// form is not valid yet (then [PlaceFormState.showErrors] is set).
  Future<String?> save() async {
    final draft = state.draft;
    if (!draft.isValid) {
      state = state.copyWith(showErrors: true);
      return null;
    }
    state = state.copyWith(saving: true);
    final photosRepo = ref.read(photosRepositoryProvider);
    final store = ref.read(photoStoreProvider);

    await ref.read(placesRepositoryProvider).save(draft.toPlace());
    for (final photo in state.photos.where((p) => p.isNew)) {
      await photosRepo.save(
        Photo(
          id: photo.id,
          ownerType: PhotoOwner.place,
          ownerId: draft.id,
          filePath: photo.path,
        ),
      );
    }
    final existing = await photosRepo
        .watchFor(PhotoOwner.place, draft.id)
        .first;
    for (final photo in existing.where(
      (p) => _removedPhotoIds.contains(p.id),
    )) {
      await photosRepo.delete(photo.id);
      await store.deleteFile(photo.filePath);
    }
    _saved = true;
    if (ref.mounted) state = state.copyWith(saving: false, savedId: draft.id);
    return draft.id;
  }
}

String locationFailureText(LocationStatus status) => switch (status) {
  LocationStatus.ok => '',
  LocationStatus.permissionDenied =>
    'Location permission was denied. You can drop the pin by hand.',
  LocationStatus.permissionDeniedForever => 'Location is blocked for Daftar. Allow it in Android settings, or drop the pin by hand.',
  LocationStatus.serviceDisabled =>
    'Turn on location (GPS) to use "I\'m here", or drop the pin by hand.',
  LocationStatus.failed =>
    "Couldn't get your position. Try again or drop the pin by hand.",
};

final placeFormProvider = NotifierProvider.autoDispose
    .family<PlaceFormNotifier, PlaceFormState, String?>(PlaceFormNotifier.new);
