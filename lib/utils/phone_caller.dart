import 'package:url_launcher/url_launcher.dart';

Future<void> callNumber(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (!await launchUrl(uri)) {
    throw 'Could not launch $uri';
  }
}

