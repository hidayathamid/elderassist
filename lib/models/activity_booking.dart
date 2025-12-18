enum BookingStatus { pending, ongoing, completed, cancelled }

class ActivityBooking {
  const ActivityBooking({
    required this.id,
    required this.caregiverId,
    required this.caregiverName,
    required this.personId,
    required this.addressId,
    required this.personName,
    required this.personAddress,
    required this.service,
    required this.date,
    required this.time,
    required this.scheduledDate,
    required this.startTime,
    required this.endTime,
    required this.paymentMethod,
    required this.servicePrice,
    required this.status,
    this.notes,
    required this.rawStatus,
    this.cancellationReason,
  });

  final String id;
  final String caregiverId;
  final String caregiverName;
  final String personId;
  final String addressId;
  final String personName;
  final String personAddress;
  final String service;
  final String date;
  final String time;
  final String scheduledDate;
  final String startTime;
  final String endTime;
  final String paymentMethod;
  final double servicePrice;
  final BookingStatus status;
  final String? notes;
  final String rawStatus;
  final String? cancellationReason;
}
