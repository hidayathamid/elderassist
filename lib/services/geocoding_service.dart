import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

const String _defaultGoogleMapsApiKey =
    'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark';
const String _googleMapsApiEnvName = 'GOOGLE_MAPS_API_KEY';

String get googleMapsApiKey => const String.fromEnvironment(
  _googleMapsApiEnvName,
  defaultValue: _defaultGoogleMapsApiKey,
);

Future<LatLng?> geocodeAddress(String address) async {
  final key = googleMapsApiKey;
  final trimmed = address.trim();
  if (key.isEmpty || trimmed.isEmpty) return null;

  final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
    'address': trimmed,
    'key': key,
  });

  try {
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    if ((decoded['status'] as String?) != 'OK') return null;
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map<String, dynamic>) return null;
    final geometry = first['geometry'];
    if (geometry is! Map<String, dynamic>) return null;
    final location = geometry['location'];
    if (location is! Map<String, dynamic>) return null;
    final lat = location['lat'];
    final lng = location['lng'];
    if (lat is num && lng is num) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
  } catch (_) {}

  return null;
}
