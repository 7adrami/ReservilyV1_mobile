import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/reservation.dart';

/// Reservation endpoints for customers.
class ReservationService {
  ReservationService(this.api);

  final ApiClient api;

  Future<List<Reservation>> list() async {
    final data = await api.request('/api/reservations/') as Map<String, dynamic>;
    return (data['reservations'] as List<dynamic>? ?? [])
        .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Reservation> create({
    required String shopSlug,
    required int barberId,
    required int serviceId,
    required DateTime date,
    required String startTime,
    required List<int> paymentProofBytes,
    required String paymentProofName,
    String? notes,
  }) async {
    final data = await api.upload(
      '/api/reservations/',
      fields: {
        'shop': shopSlug,
        'barber': '$barberId',
        'service': '$serviceId',
        'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'start_time': startTime,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      file: MultipartFile.fromBytes(paymentProofBytes,
          filename: paymentProofName),
      fileField: 'payment_proof',
    ) as Map<String, dynamic>;
    return Reservation.fromJson(data['reservation'] as Map<String, dynamic>);
  }

  Future<void> cancel(int pk) async {
    await api.request('/api/reservations/$pk/cancel/', method: 'POST');
  }

  /// Barber / staff: transition a reservation's status.
  Future<void> setStatus(int pk, String status) async {
    await api.request(
      '/api/reservations/$pk/status/',
      method: 'POST',
      body: {'status': status},
    );
  }

  /// Loads daily availability slots for a barber.
  Future<Availability> availability({
    required int barberId,
    DateTime? date,
    String? shopSlug,
    int? serviceId,
  }) async {
    final data = await api.request(
      '/api/barbers/availability/',
      query: {
        'barber': '$barberId',
        if (date != null) 'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        if (shopSlug != null) 'shop': shopSlug,
        if (serviceId != null) 'service': '$serviceId',
      },
    ) as Map<String, dynamic>;
    return Availability.fromJson(data);
  }

  /// Ensures the picker can build an 8MB-limited upload before sending.
  static bool proofAllowed(int byteLength) => byteLength <= 8 * 1024 * 1024;
}
