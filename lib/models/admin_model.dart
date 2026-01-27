class AdminModel {
  AdminModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
  });

  final String uid;
  final String name;
  final String email;
  final String role;

  factory AdminModel.fromMap(String uid, Map<String, dynamic> data) {
    return AdminModel(
      uid: uid,
      name: ((data['name'] as String?) ?? '').trim(),
      email: ((data['email'] as String?) ?? '').trim(),
      role: ((data['role'] as String?) ?? 'admin').trim(),
    );
  }

  static AdminModel safeFromMap(String uid, Map<String, dynamic>? data) {
    return AdminModel.fromMap(uid, data ?? const <String, dynamic>{});
  }
}

