/// User account information as returned by the API.
class User {
  const User({
    required this.id,
    required this.username,
    required this.name,
    this.firstName,
    this.lastName,
    required this.role,
    this.email,
    this.phone,
    this.avatar,
    this.waitingListVisible = false,
    this.hasKey = false,
    this.ownedShopSlug,
  });

  final int id;
  final String username;
  final String name;
  final String? firstName;
  final String? lastName;
  final String role;
  final String? email;
  final String? phone;
  final String? avatar;
  final bool waitingListVisible;
  final bool hasKey;
  final String? ownedShopSlug;

  static const String roleCustomer = 'customer';
  static const String roleBarber = 'barber';
  static const String roleOwner = 'shop_owner';
  static const String roleAdmin = 'admin';

  bool get isCustomer => role == roleCustomer;
  bool get isBarber => role == roleBarber;
  bool get isOwner => role == roleOwner;
  bool get isAdmin => role == roleAdmin;

  User copyWith({
    String? name,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? avatar,
    bool? waitingListVisible,
  }) {
    return User(
      id: id,
      username: username,
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatar: avatar ?? this.avatar,
      waitingListVisible: waitingListVisible ?? this.waitingListVisible,
      hasKey: hasKey,
      ownedShopSlug: ownedShopSlug,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      name: (json['name'] ?? json['username']) as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      role: json['role'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      avatar: json['avatar'] as String?,
      waitingListVisible: json['waiting_list_visible'] == true,
      hasKey: json['has_key'] == true,
      ownedShopSlug: json['owned_shop_slug'] as String?,
    );
  }
}
