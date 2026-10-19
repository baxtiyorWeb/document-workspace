class UserProfile {
  final String id;
  final String email;
  final String fullName;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
  };
}

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserProfile? user;
  final String? accessToken;
  final String? refreshToken;
  final String? errorMessage;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.user,
    this.accessToken,
    this.refreshToken,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserProfile? user,
    String? accessToken,
    String? refreshToken,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
