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
  final isUpcoming =
      normalizedStatus == 'SCHEDULED' ||
      normalizedStatus == 'PENDING' ||
      normalizedStatus == 'READY';
  if (!isUpcoming) return normalizedStatus;

  final nowEpoch = DateTime.now().millisecondsSinceEpoch;
  final scheduledEpoch = parseMalaysiaEpoch(date: date, time: time);
  if (scheduledEpoch != null) {
    return scheduledEpoch > nowEpoch ? normalizedStatus : 'ASSIGNED';
  }

  // Fallback: date-only compare.
  final normalizedDate = _normalizeMalaysiaDateToIso(date);
  if (normalizedDate != null) {
    final malaysiaToday = malaysiaTodayString();
    if (normalizedDate.compareTo(malaysiaToday) > 0) return normalizedStatus;
    return 'ASSIGNED';
  }

  return normalizedStatus;
}

int? parseMalaysiaEpoch({required String date, required String time}) {
  final d = _normalizeMalaysiaDateToIso(date);
  if (d == null) return null;
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
  if (raw.isEmpty) return '00:00';
  if (RegExp(r'^\d{2}:\d{2}$').hasMatch(raw)) return raw;
  if (RegExp(r'^\d{1,2}:\d{2}:\d{2}$').hasMatch(raw)) {
    final parts = raw.split(':');
    final hh = parts[0].padLeft(2, '0');
    return '$hh:${parts[1]}';
  }

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

String? _normalizeMalaysiaDateToIso(String date) {
  final trimmed = date.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
  if (RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(trimmed)) {
    return trimmed.replaceAll('/', '-');
  }

  final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(trimmed);
  if (slash != null) {
    final dd = int.tryParse(slash.group(1) ?? '');
    final mm = int.tryParse(slash.group(2) ?? '');
    final yyyy = int.tryParse(slash.group(3) ?? '');
    if (dd == null || mm == null || yyyy == null) return null;
    if (dd < 1 || dd > 31) return null;
    if (mm < 1 || mm > 12) return null;
    return '${yyyy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}';
  }

  final dash = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(trimmed);
  if (dash != null) {
    final dd = int.tryParse(dash.group(1) ?? '');
    final mm = int.tryParse(dash.group(2) ?? '');
    final yyyy = int.tryParse(dash.group(3) ?? '');
    if (dd == null || mm == null || yyyy == null) return null;
    if (dd < 1 || dd > 31) return null;
    if (mm < 1 || mm > 12) return null;
    return '${yyyy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}';
  }

  return null;
}

String malaysiaTodayString() {
  final malaysiaEpoch = DateTime.now().millisecondsSinceEpoch + 8 * 60 * 60 * 1000;
  return DateTime.fromMillisecondsSinceEpoch(malaysiaEpoch, isUtc: true)
      .toIso8601String()
      .substring(0, 10);
}
