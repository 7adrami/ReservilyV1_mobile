/// A barbershop as returned by the API.
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.slug,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.description,
    this.phone,
    required this.opensAt,
    required this.closesAt,
    this.photo,
    this.averageRating,
    this.ratingCount = 0,
    this.isActive = true,
    this.distanceKm,
    this.barbers = const [],
    this.reviews = const [],
    this.myRating,
  });

  final int id;
  final String name;
  final String slug;
  final String address;
  final String city;
  final double latitude;
  final double longitude;
  final String? description;
  final String? phone;
  final String opensAt;
  final String closesAt;
  final String? photo;
  final double? averageRating;
  final int ratingCount;
  final bool isActive;
  final double? distanceKm;
  final List<BarberItem> barbers;
  final List<ReviewItem> reviews;

  /// The signed-in user's own star rating for this shop (1-5), if any.
  final int? myRating;

  String get ratingLabel =>
      averageRating == null ? 'New' : averageRating!.toStringAsFixed(1);

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      phone: json['phone'] as String?,
      opensAt: json['opens_at'] as String? ?? '09:00',
      closesAt: json['closes_at'] as String? ?? '21:30',
      photo: json['photo'] as String?,
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int? ?? 0,
      isActive: json['is_active'] != false,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      barbers: (json['barbers'] as List<dynamic>? ?? [])
          .map((e) => BarberItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviews: (json['reviews'] as List<dynamic>? ?? [])
          .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      myRating: json['my_rating'] as int?,
    );
  }
}

class BarberItem {
  const BarberItem({
    required this.id,
    required this.name,
    required this.username,
    this.phone,
    this.avatar,
    this.photo,
    this.bio,
    this.specialty,
    this.averageRating,
    this.ratingCount = 0,
    this.services = const [],
    this.isActive = true,
    this.myRating,
    this.reviews = const [],
    this.shops = const [],
  });

  final int id;
  final String name;
  final String username;
  final String? phone;
  final String? avatar;
  final String? photo;
  final String? bio;
  final String? specialty;
  final double? averageRating;
  final int ratingCount;
  final List<ServiceItem> services;
  final bool isActive;

  /// The signed-in user's own star rating for this barber (1-5), if any.
  final int? myRating;
  final List<ReviewItem> reviews;
  final List<BarberShop> shops;

  factory BarberItem.fromJson(Map<String, dynamic> json) {
    return BarberItem(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String,
      phone: json['phone'] as String?,
      avatar: json['avatar'] as String?,
      photo: json['photo'] as String?,
      bio: json['bio'] as String?,
      specialty: json['specialty'] as String?,
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int? ?? 0,
      services: (json['services'] as List<dynamic>? ?? [])
          .map((e) => ServiceItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      isActive: json['is_active'] != false,
      myRating: json['my_rating'] as int?,
      reviews: (json['reviews'] as List<dynamic>? ?? [])
          .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      shops: (json['shops'] as List<dynamic>? ?? [])
          .map((e) => BarberShop.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A barbershop a barber works at (from the barber detail response).
class BarberShop {
  const BarberShop({required this.id, required this.slug, required this.name, this.city});

  final int id;
  final String slug;
  final String name;
  final String? city;

  factory BarberShop.fromJson(Map<String, dynamic> json) {
    return BarberShop(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      city: json['city'] as String?,
    );
  }
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.durationMinutes,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? description;
  final double price;
  final int durationMinutes;
  final bool isActive;

  String get priceLabel => price.toStringAsFixed(2);

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    return ServiceItem(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: double.parse(json['price'].toString()),
      durationMinutes: json['duration_minutes'] as int? ?? 30,
      isActive: json['is_active'] != false,
    );
  }
}

class ReviewItem {
  const ReviewItem({
    required this.id,
    this.userName,
    this.userUsername,
    this.avatar,
    this.body,
    this.createdAt,
    this.waitingListVisible = true,
  });

  final int id;
  final String? userName;
  final String? userUsername;
  final String? avatar;
  final String? body;
  final DateTime? createdAt;

  /// Whether the author agreed to be shown on public lists; when false the
  /// review is displayed as "Anonymous".
  final bool waitingListVisible;

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      id: json['id'] as int,
      userName: json['user_name'] as String?,
      userUsername: json['user_username'] as String?,
      avatar: json['avatar'] as String?,
      body: json['body'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      waitingListVisible: json['waiting_list_visible'] != false,
    );
  }
}

/// Booking options for a shop: the barbers and services to pick from.
class BookingOptions {
  const BookingOptions({required this.barbers, required this.services});

  final List<BookingBarber> barbers;
  final List<BookingService> services;

  factory BookingOptions.fromJson(Map<String, dynamic> json) {
    return BookingOptions(
      barbers: (json['barbers'] as List<dynamic>? ?? [])
          .map((e) => BookingBarber.fromJson(e as Map<String, dynamic>))
          .toList(),
      services: (json['services'] as List<dynamic>? ?? [])
          .map((e) => BookingService.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BookingBarber {
  const BookingBarber({
    required this.pk,
    required this.name,
    required this.username,
    this.phone,
    this.wallets = const [],
  });

  final int pk;
  final String name;
  final String username;
  final String? phone;
  final List<Map<String, String>> wallets;

  factory BookingBarber.fromJson(Map<String, dynamic> json) {
    return BookingBarber(
      pk: json['pk'] as int,
      name: json['name'] as String,
      username: json['username'] as String,
      phone: json['phone'] as String?,
      wallets: (json['wallets'] as List<dynamic>? ?? [])
          .map((e) => (e as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, v.toString()),
              ))
          .toList(),
    );
  }
}

class BookingService {
  const BookingService({
    required this.pk,
    required this.name,
    required this.durationMinutes,
    this.price,
  });

  final int pk;
  final String name;
  final int durationMinutes;
  final double? price;

  factory BookingService.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    return BookingService(
      pk: json['pk'] as int,
      name: json['name'] as String,
      durationMinutes: json['duration_minutes'] as int? ?? 30,
      price: rawPrice == null
          ? null
          : rawPrice is num
              ? rawPrice.toDouble()
              : double.tryParse(rawPrice.toString()),
    );
  }
}
