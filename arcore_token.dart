class ArcoreToken {
  final String token;
  final DateTime expiration;
  final String appVersion;
  final DateTime createdAt;

  final String? predecessorToken;
  final String? successorToken;
  final bool isRefreshing;
  final String? error;

  ArcoreToken({
    required this.token,
    required this.expiration,
    required this.appVersion,
    required this.createdAt,
    this.predecessorToken,
    this.successorToken,
    this.isRefreshing = false,
    this.error,
  });

  bool get isValid => DateTime.now().isBefore(expiration);

  /// Returns true if 75% of the token's lifespan has passed.
  bool get isRefreshable {
    final totalDuration = expiration.difference(createdAt);
    final elapsed = DateTime.now().difference(createdAt);
    return elapsed.inSeconds >= (totalDuration.inSeconds * 0.75);
  }

  bool get needsRefresh => isRefreshable;

  Map<String, dynamic> toJson() => {
    'token': token,
    'expiration': expiration.millisecondsSinceEpoch ~/ 1000,
    'appVersion': appVersion,
    'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
    'predecessorToken': predecessorToken,
    'successorToken': successorToken,
    'isRefreshing': isRefreshing,
    'error': error,
  };

  factory ArcoreToken.fromJson(Map<String, dynamic> json) {
    if (json['token'] == null) {
      throw const FormatException('Missing required field: token');
    }
    if (json['expiration'] == null) {
      throw const FormatException('Missing required field: expiration');
    }
    if (json['createdAt'] == null) {
      throw const FormatException('Missing required field: createdAt');
    }

    return ArcoreToken(
      token: json['token'],
      expiration: DateTime.fromMillisecondsSinceEpoch(
        json['expiration'] * 1000,
      ),
      appVersion: json['appVersion'] ?? 'unknown',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] * 1000),
      predecessorToken: json['predecessorToken'],
      successorToken: json['successorToken'],
      isRefreshing: json['isRefreshing'] ?? false,
      error: json['error'],
    );
  }

  @override
  String toString() {
    return 'ArcoreToken(token: ${token.substring(0, 10)}..., expiration: $expiration, appVersion: $appVersion, predecessor: $predecessorToken, successor: $successorToken, isRefreshing: $isRefreshing, error: $error)';
  }
}
