/// Google Maps style JSON for the dark theme (Android `GoogleMap.style`).
///
/// A neutral dark grey map that sits behind Daftar's dark surfaces. These are
/// the map provider's style keys, so the colours are literal hex values here
/// and are the one place outside `DaftarColors` allowed to hold them.
/// Generated in the spirit of https://mapstyle.withgoogle.com/ ("Night").
const String darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#16181c"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#8e949c"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#16181c"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#2b2f35"}]},
  {"featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{"color": "#a4aab1"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#b9bec4"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#7d838b"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1a2320"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#5f7a6c"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#262a30"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#16181c"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8e949c"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#32373e"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1c1f24"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#b9bec4"}]},
  {"featureType": "transit", "elementType": "labels.text.fill", "stylers": [{"color": "#7d838b"}]},
  {"featureType": "transit.station", "elementType": "geometry", "stylers": [{"color": "#1f2328"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0d1014"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#4b5158"}]}
]
''';
