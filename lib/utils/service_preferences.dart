String extractServiceLabelFromFirestore(Map<String, dynamic> data) {
  final raw =
      data['servicePreferences'] ?? data['service'] ?? data['services'] ?? '';
  return extractServiceLabel(raw);
}

String extractServiceLabel(Object? raw) {
  if (raw is String) return raw.trim();
  if (raw is Iterable) {
    final values =
        raw
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
    return values.join(', ');
  }
  return '';
}

List<String> extractServicePreferencesList(Object? raw) {
  if (raw is Iterable) {
    return raw
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return [raw.trim()];
  }
  return const [];
}

