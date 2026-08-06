import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/shop.dart';

/// Shops & barbers endpoints (public catalog, booking options).
class ShopService {
  ShopService(this.api);

  final ApiClient api;

  Future<List<Shop>> listShops({String? query, String? city, double? lat, double? lng}) async {
    final data = await api.request(
      '/api/shops/',
      query: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (city != null && city.isNotEmpty) 'city': city,
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
      },
    ) as Map<String, dynamic>;
    return (data['shops'] as List<dynamic>? ?? [])
        .map((e) => Shop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> cities() async {
    final data = await api.request('/api/shops/cities/') as Map<String, dynamic>;
    return (data['cities'] as List<dynamic>? ?? []).cast<String>();
  }

  Future<Shop> shopDetail(String slug) async {
    final data = await api.request('/api/shops/$slug/') as Map<String, dynamic>;
    return Shop.fromJson(data['shop'] as Map<String, dynamic>);
  }

  Future<BookingOptions> bookingOptions(String slug, {int? service, int? barber}) async {
    final data = await api.request(
      '/api/shops/$slug/booking-options/',
      query: {
        if (service != null) 'service': '$service',
        if (barber != null) 'barber': '$barber',
      },
    ) as Map<String, dynamic>;
    return BookingOptions.fromJson(data);
  }

  Future<Map<String, dynamic>> barberDetail(int pk) async {
    final data = await api.request('/api/barbers/$pk/') as Map<String, dynamic>;
    return data['barber'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> barberSchedule(int pk, {DateTime? date, String? shopSlug}) async {
    return (await api.request(
      '/api/barbers/$pk/schedule/',
      query: {
        if (date != null) 'date': _fmtDate(date),
        if (shopSlug != null) 'shop': shopSlug,
      },
    )) as Map<String, dynamic>;
  }

  Future<void> rateBarber(int pk, int score) async {
    await api.request(
      '/api/barbers/$pk/rate/',
      method: 'POST',
      body: {'score': score},
    );
  }

  Future<void> reviewBarber(int pk, String body) async {
    await api.request(
      '/api/barbers/$pk/review/',
      method: 'POST',
      body: {'body': body},
    );
  }

  static String fmtDate(DateTime d) => _fmtDate(d);

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------- barber self-service

  Future<Map<String, dynamic>> barberDashboard() async {
    return (await api.request('/api/barber/dashboard/')) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> barberHours({String? shopSlug}) async {
    return (await api.request(
      '/api/barber/hours/',
      query: {if (shopSlug != null) 'shop': shopSlug},
    )) as Map<String, dynamic>;
  }

  Future<void> saveBarberHours({
    required String shopSlug,
    required List<Map<String, dynamic>> schedule,
  }) async {
    await api.request(
      '/api/barber/hours/',
      method: 'PUT',
      body: {'shop': shopSlug, 'schedule': schedule},
    );
  }

  Future<List<Map<String, dynamic>>> barberStyles() async {
    final data = await api.request('/api/barber/styles/') as Map<String, dynamic>;
    return ((data['services'] as List<dynamic>? ?? [])).cast<Map<String, dynamic>>();
  }

  Future<int> addBarberStyle({
    required String name,
    required String price,
    int? durationMinutes,
    String? description,
  }) async {
    final data = await api.request(
      '/api/barber/styles/',
      method: 'POST',
      body: {
        'name': name,
        'price': price,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        if (description != null && description.isNotEmpty) 'description': description,
      },
    ) as Map<String, dynamic>;
    return data['id'] as int;
  }

  Future<void> updateBarberStyle(int pk, {String? name, String? price, int? durationMinutes}) async {
    await api.request(
      '/api/barber/styles/$pk/',
      method: 'PUT',
      body: {
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      },
    );
  }

  Future<void> deleteBarberStyle(int pk) async {
    await api.request('/api/barber/styles/$pk/', method: 'DELETE');
  }

  Future<Map<String, dynamic>> barberRequests() async {
    return (await api.request('/api/barber/requests/')) as Map<String, dynamic>;
  }

  Future<void> sendBarberRequest(int shopId, String kind, {String? note}) async {
    await api.request(
      '/api/barber/requests/',
      method: 'POST',
      body: {
        'shop': '$shopId',
        'kind': kind,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  Future<void> cancelBarberRequest(int pk) async {
    await api.request('/api/barber/requests/', method: 'POST', body: {'cancel': '$pk'});
  }

  Future<Map<String, dynamic>> myWallets() async {
    return (await api.request('/api/auth/me/wallets/')) as Map<String, dynamic>;
  }

  Future<void> saveWallets(List<Map<String, dynamic>> wallets) async {
    await api.request(
      '/api/auth/me/wallets/',
      method: 'PUT',
      body: {'wallets': wallets},
    );
  }

  // ----------------------------------------------------------- owner dashboard

  Future<Map<String, dynamic>> ownerShop() async {
    return (await api.request('/api/owner/shop/')) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateOwnerShop(
    Map<String, dynamic> fields, {
    List<int>? photoBytes,
    String? photoFilename,
  }) async {
    if (photoBytes != null) {
      final form = FormData();
      fields.forEach((k, v) => form.fields.add(MapEntry(k, v.toString())));
      form.files.add(MapEntry(
        'photo',
        MultipartFile.fromBytes(photoBytes, filename: photoFilename ?? 'photo.jpg'),
      ));
      return (await api.request(
        '/api/owner/shop/',
        method: 'PATCH',
        form: true,
        body: form,
      )) as Map<String, dynamic>;
    }
    return (await api.request('/api/owner/shop/', method: 'PATCH', body: fields))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> ownerTeam() async {
    return (await api.request('/api/owner/team/')) as Map<String, dynamic>;
  }

  Future<void> addBarberToTeam({required String username, required String email}) async {
    await api.request(
      '/api/owner/team/',
      method: 'POST',
      body: {'username': username, 'email': email},
    );
  }

  Future<void> toggleBarber(int pk) async {
    await api.request('/api/owner/team/$pk/toggle/', method: 'POST');
  }

  Future<Map<String, dynamic>> ownerRequests() async {
    return (await api.request('/api/owner/requests/')) as Map<String, dynamic>;
  }

  Future<void> resolveRequest(int pk, String action) async {
    await api.request(
      '/api/owner/requests/',
      method: 'POST',
      body: {'request': '$pk', 'action': action},
    );
  }

  // --------------------------------------------------------------- admin

  Future<void> adminCreateOwner(String username, String email) async {
    await api.request(
      '/api/admin/owners/',
      method: 'POST',
      body: {'username': username, 'email': email},
    );
  }

  Future<List<Map<String, dynamic>>> adminBroadcasts() async {
    final data = await api.request('/api/admin/broadcasts/') as Map<String, dynamic>;
    return ((data['broadcasts'] as List<dynamic>? ?? [])).cast<Map<String, dynamic>>();
  }

  Future<void> createBroadcast(String message, {String audience = 'all'}) async {
    await api.request(
      '/api/admin/broadcasts/',
      method: 'POST',
      body: {'message': message, 'audience': audience},
    );
  }
}
