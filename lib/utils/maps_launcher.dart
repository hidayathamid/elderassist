import 'package:url_launcher/url_launcher.dart';

class MapsLauncherHelper {
  static Future<bool> openCoordinates({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng${label != null ? '&query_place_id=${Uri.encodeComponent(label)}' : ''}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> openQuery(String query) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

