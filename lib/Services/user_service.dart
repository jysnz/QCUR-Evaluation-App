class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    return null; // Stub
  }

  Future<void> updateProfile({required String name, String? imageUrl}) async {
    // Stub
  }
}
