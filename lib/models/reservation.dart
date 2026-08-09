/// A barber reservation as returned by the API.
class Reservation {
  const Reservation({
    required this.id,
    this.shop,
    this.barber,
    this.customer,
    this.service,
    required this.date,
    required this.startTime,
    this.endTime,
    this.paymentProof,
    required this.status,
    this.notes,
    required this.createdAt,
    this.position,
    this.waitMinutes,
  });

  final int id;
  final Map<String, dynamic>? shop;
  final Map<String, dynamic>? barber;
  final Map<String, dynamic>? customer;
  final Map<String, dynamic>? service;
  final DateTime date;
  final String startTime;
  final String? endTime;
  final String? paymentProof;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final int? position;
  final int? waitMinutes;

  static const String statusPending = 'pending';
  static const String statusConfirmed = 'confirmed';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';

  String get shopName => shop?['name'] as String? ?? '—';
  String? get shopSlug => shop?['slug'] as String?;
  String get barberName => barber?['name'] as String? ?? '—';
  String get customerName => customer?['name'] as String? ?? '—';
  String get customerUsername => customer?['username'] as String? ?? '';
  String get customerPhone => customer?['phone'] as String? ?? '—';
  String get serviceName => service?['name'] as String? ?? '—';
  String get servicePrice => service?['price']?.toString() ?? '—';
  String get city => shop?['city'] as String? ?? '';

  bool get isPending => status == statusPending;
  bool get isConfirmed => status == statusConfirmed;
  bool get isCancelled => status == statusCancelled;
  bool get isActive => isPending || isConfirmed;
  bool get canCancel => isActive;

  String get statusLabel {
    switch (status) {
      case statusPending:
        return 'Pending';
      case statusConfirmed:
        return 'Confirmed';
      case statusCompleted:
        return 'Completed';
      case statusCancelled:
        return 'Cancelled';
      default:
        return status;
    }
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      id: json['id'] as int,
      shop: json['shop'] as Map<String, dynamic>?,
      barber: json['barber'] as Map<String, dynamic>?,
      customer: json['customer'] as Map<String, dynamic>?,
      service: json['service'] as Map<String, dynamic>?,
      date: DateTime.parse(json['date'] as String),
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String?,
      paymentProof: json['payment_proof'] as String?,
      status: json['status'] as String,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      position: json['position'] as int?,
      waitMinutes: json['wait_minutes'] as int?,
    );
  }
}

/// Daily availability: time slots with open/closed flags and existing bookings.
class Availability {
  const Availability({
    required this.date,
    required this.duration,
    required this.slots,
    required this.bookings,
  });

  final DateTime date;
  final int duration;
  final List<TimeSlot> slots;
  final List<BookingStub> bookings;

  factory Availability.fromJson(Map<String, dynamic> json) {
    return Availability(
      date: DateTime.parse(json['date'] as String),
      duration: json['duration'] as int? ?? 30,
      slots: (json['slots'] as List<dynamic>? ?? [])
          .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
      bookings: (json['bookings'] as List<dynamic>? ?? [])
          .map((e) => BookingStub.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TimeSlot {
  const TimeSlot({required this.time, required this.open});

  final String time;
  final bool open;

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    return TimeSlot(
      time: json['time'] as String,
      open: json['open'] == true,
    );
  }
}

class BookingStub {
  const BookingStub({required this.id, required this.time, required this.status});

  final int id;
  final String time;
  final String status;

  factory BookingStub.fromJson(Map<String, dynamic> json) {
    return BookingStub(
      id: json['id'] as int,
      time: json['time'] as String,
      status: json['status'] as String,
    );
  }
}

/// A barber's daily queue (schedule view).
class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.time,
    this.customerName,
    this.customerUsername,
    this.service,
    required this.status,
    this.position,
    this.estimatedWaitMinutes,
    this.visible = true,
    this.isMine = false,
  });

  final int id;
  final String time;
  final String? customerName;
  final String? customerUsername;
  final String? service;
  final String status;
  final int? position;
  final int? estimatedWaitMinutes;
  final bool visible;
  final bool isMine;

  factory QueueEntry.fromJson(Map<String, dynamic> json) {
    return QueueEntry(
      id: json['id'] as int,
      time: json['time'] as String,
      customerName: json['customer_name'] as String?,
      customerUsername: json['customer_username'] as String?,
      service: json['service'] as String?,
      status: json['status'] as String,
      position: json['position'] as int?,
      estimatedWaitMinutes: json['estimated_wait_minutes'] as int?,
      visible: json['visible'] == true,
      isMine: json['is_mine'] == true,
    );
  }
}
