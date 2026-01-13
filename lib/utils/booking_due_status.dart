String normalizeBookingStatus(String value) {
  return value
      .trim()
      .toUpperCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_')
      .replaceAll('__', '_');
}

String deriveDueAwareStatus({
  required String status,
  required String date,
  required String time,
}) {
  final normalizedStatus = normalizeBookingStatus(status);
  if (normalizedStatus != 'SCHEDULED') return normalizedStatus;

  final nowEpoch = DateTime.now().millisecondsSinceEpoch;
  final scheduledEpoch = parseMalaysiaEpoch(date: date, time: time);
  if (scheduledEpoch != null) {
    return scheduledEpoch > nowEpoch ? 'SCHEDULED' : 'ASSIGNED';
  }

  // Fallback: date-only compare (Malaysia date format).
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.trim())) {
    final malaysiaToday = malaysiaTodayString();
    if (date.trim().compareTo(malaysiaToday) > 0) return 'SCHEDULED';
    return 'ASSIGNED';
  }

  return normalizedStatus;
}

int? parseMalaysiaEpoch({required String date, required String time}) {
  final d = date.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) return null;
  final time24 = normalizeTo24HourTime(time);
  final iso = '${d}T$time24:00+08:00';
  try {
    return DateTime.parse(iso).millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }
}

String normalizeTo24HourTime(String time) {
  final raw = time.trim().toLowerCase();
  if (RegExp(r'^\d{2}:\d{2}$').hasMatch(raw)) return raw;

  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$').firstMatch(raw);
  if (match != null) {
    var h = int.tryParse(match.group(1) ?? '');
    final m = int.tryParse(match.group(2) ?? '');
    final period = match.group(3) ?? '';
    if (h == null || m == null) return '00:00';
    h = h.clamp(0, 12);
    final mm = m.clamp(0, 59);
    if (period == 'am') {
      if (h == 12) h = 0;
    } else {
      if (h != 12) h += 12;
    }
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  return '00:00';
}

String malaysiaTodayString() {
  final malaysiaEpoch = DateTime.now().millisecondsSinceEpoch + 8 * 60 * 60 * 1000;
  return DateTime.fromMillisecondsSinceEpoch(malaysiaEpoch, isUtc: true)
      .toIso8601String()
      .substring(0, 10);
}
