class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.gender,
    required this.city,
    required this.birthDate,
    required this.phone,
  });

  final String name;
  final String email;
  final String gender;
  final String city;
  final DateTime birthDate;
  final String phone;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String,
        email: json['email'] as String,
        gender: json['gender'] as String,
        city: json['city'] as String,
        birthDate: DateTime.parse(json['birth_date'] as String),
        phone: json['phone'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'gender': gender,
        'city': city,
        'birth_date': birthDate.toIso8601String(),
        'phone': phone,
      };
}
