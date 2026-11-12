class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final email = json['email'];
    if (id is! String || name is! String || email is! String) {
      throw const FormatException('Thông tin tài khoản không hợp lệ.');
    }
    return AuthUser(id: id, name: name, email: email);
  }
}
