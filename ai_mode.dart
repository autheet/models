/// AI interaction mode for chat
enum AIMode {
  /// Standard text-based chat with gemini-2.0-flash-exp
  standard,

  /// Live bidirectional audio streaming with gemini-2.0-flash-exp
  /// Automatically activated when chat widget height is < 20% of screen
  live,
}

extension AIModeExtension on AIMode {
  String get displayName {
    switch (this) {
      case AIMode.standard:
        return 'Text Chat';
      case AIMode.live:
        return 'Live Audio';
    }
  }

  String get modelName {
    switch (this) {
      case AIMode.standard:
        return 'gemini-2.5-pro';
      case AIMode.live:
        return 'gemini-2.5-flash-live';
    }
  }

  bool get isLive => this == AIMode.live;
}
