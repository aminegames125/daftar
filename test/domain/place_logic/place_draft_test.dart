import 'package:daftar/domain/models/place.dart';
import 'package:daftar/domain/place_logic/open_now.dart';
import 'package:daftar/domain/place_logic/opening_hours_edit.dart';
import 'package:daftar/domain/place_logic/place_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceDraft', () {
    test('needs a name and a type', () {
      const draft = PlaceDraft(id: 'p1');
      expect(draft.validate(), {
        PlaceDraftError.nameRequired,
        PlaceDraftError.typeRequired,
      });
      expect(
        draft.copyWith(name: '  ').validate(),
        contains(PlaceDraftError.nameRequired),
      );
      expect(draft.copyWith(name: 'Café', typeId: 't').isValid, isTrue);
    });

    test('rating must be 1 to 5', () {
      final draft = const PlaceDraft(
        id: 'p',
        name: 'A',
        typeId: 't',
      ).copyWith(rating: 6);
      expect(draft.validate(), {PlaceDraftError.ratingOutOfRange});
      expect(draft.copyWith(rating: 5).isValid, isTrue);
      expect(
        draft.copyWith(rating: 5).copyWith(clearRating: true).rating,
        isNull,
      );
    });

    test('toPlace trims, nulls blanks and dedupes tags', () {
      final place = const PlaceDraft(
        id: 'p',
        name: '  Café Yasmine ',
        typeId: 't',
        address: ' ',
        phone: ' 71 123 456 ',
        wifiName: 'Yasmine',
        wifiPassword: ' pass word ',
        notes: '',
        tags: ['Clean', ' Clean ', 'Quiet', ''],
        paymentMethodIds: {'cash'},
        rating: 4,
      ).toPlace();
      expect(place.name, 'Café Yasmine');
      expect(place.address, isNull);
      expect(place.phone, '71 123 456');
      expect(place.wifiPassword, ' pass word ');
      expect(place.notes, isNull);
      expect(place.tags, ['Clean', 'Quiet']);
      expect(place.paymentMethodIds, ['cash']);
      expect(place.openingHours, isNull);
    });

    test('toPlace throws when invalid', () {
      expect(() => const PlaceDraft(id: 'p').toPlace(), throwsStateError);
    });

    test('fromPlace round-trips', () {
      const place = Place(
        id: 'p',
        name: 'Baker',
        typeId: 't',
        lat: 36.8,
        lng: 10.1,
        address: 'Rue 1',
        phone: '123',
        rating: 3,
        tags: ['Cheap'],
        paymentMethodIds: ['cash', 'card'],
      );
      final back = PlaceDraft.fromPlace(place).toPlace();
      expect(back.name, place.name);
      expect(back.lat, 36.8);
      expect(back.tags, ['Cheap']);
      expect(back.paymentMethodIds, ['cash', 'card']);
      expect(back.rating, 3);
    });

    test('clearLocation removes both coordinates', () {
      final draft = const PlaceDraft(
        id: 'p',
        lat: 1,
        lng: 2,
      ).copyWith(clearLocation: true);
      expect(draft.hasLocation, isFalse);
    });

    test('empty opening hours are not saved', () {
      final place = const PlaceDraft(
        id: 'p',
        name: 'A',
        typeId: 't',
        openingHours: OpeningHours({}),
      ).toPlace();
      expect(place.openingHours, isNull);
    });
  });

  group('phone helpers', () {
    test('cleanPhone drops letters', () {
      expect(
        cleanPhone('Tel: +216 71-123.456'),
        '+216 71-123.456'.replaceAll('Tel: ', ''),
      );
    });

    test('dialablePhone keeps digits and a leading plus', () {
      expect(dialablePhone('+216 71 123 456'), '+21671123456');
      expect(dialablePhone('(71) 123-456'), '71123456');
    });
  });

  group('opening hours editing', () {
    test('default week is open every day', () {
      final h = defaultOpeningHours();
      expect(h.days.keys, weekdayKeys);
      expect(h.days['mon'], [(open: '08:00', close: '22:00')]);
    });

    test('setDay replaces, closes and clears a day', () {
      var h = defaultOpeningHours();
      h = setDay(h, 'sun', []);
      expect(h.days['sun'], isEmpty);
      h = setDay(h, 'sat', null);
      expect(h.days.containsKey('sat'), isFalse);
      h = setDay(null, 'mon', [(open: '09:00', close: '12:00')]);
      expect(h.days.keys, ['mon']);
    });

    test('copyDayToAll', () {
      final h = copyDayToAll(
        setDay(null, 'mon', [
          (open: '09:00', close: '12:00'),
          (open: '14:00', close: '18:00'),
        ]),
        'mon',
      );
      expect(h.days.keys, weekdayKeys);
      expect(h.days['sun'], hasLength(2));
    });

    test('groupHours merges consecutive identical days', () {
      var h = defaultOpeningHours();
      h = setDay(h, 'sun', []);
      h = setDay(h, 'wed', [
        (open: '08:00', close: '13:00'),
        (open: '15:00', close: '22:00'),
      ]);
      expect(groupHours(h), [
        (days: 'Mon–Tue', hours: '08:00–22:00'),
        (days: 'Wed', hours: '08:00–13:00, 15:00–22:00'),
        (days: 'Thu–Sat', hours: '08:00–22:00'),
        (days: 'Sun', hours: 'Closed'),
      ]);
    });

    test('groupHours skips unknown days and does not merge across gaps', () {
      const h = OpeningHours({
        'mon': [(open: '08:00', close: '12:00')],
        'wed': [(open: '08:00', close: '12:00')],
      });
      expect(groupHours(h).map((g) => g.days), ['Mon', 'Wed']);
    });

    test('rangesAreValid', () {
      expect(rangesAreValid([(open: '08:00', close: '12:00')]), isTrue);
      expect(rangesAreValid([(open: '8', close: '12:00')]), isFalse);
    });
  });
}
