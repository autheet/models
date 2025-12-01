/// AI-related model classes
///
/// This file consolidates all AI-related data models and enums used throughout
/// the application, including mode configurations and route-specific AI context.
library;

/// AI interaction mode for chat
enum AIMode {
  /// Standard text-based chat with gemini-2.5-pro
  standard,

  /// Live bidirectional audio streaming with gemini-2.5-flash-live
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

/// Configuration for route-specific AI system prompts
///
/// This class encapsulates the system prompt configuration that can be
/// attached to routes to provide context-aware AI assistance.
class AIRouteContext {
  /// The route path this context applies to
  final String path;

  /// Route-specific system prompt part to be combined with base prompt
  final String? systemPromptPart;

  /// Human-readable description of the route
  final String description;

  /// Optional suggestions to display in the chat UI for this route
  /// These suggestions help users interact with AI on this specific screen
  final List<String>? suggestions;

  /// Optional welcome messages to display in the chat UI for this route
  /// A random message from this list will be shown to the user
  final List<String>? welcomeMessages;

  const AIRouteContext({
    required this.path,
    this.systemPromptPart,
    required this.description,
    this.suggestions,
    this.welcomeMessages,
  });

  /// Combines the route-specific prompt with a base system prompt
  String buildSystemPrompt(String basePrompt) {
    if (systemPromptPart == null || systemPromptPart!.isEmpty) {
      return basePrompt;
    }

    return '''
$basePrompt

--- CURRENT SCREEN CONTEXT ---
$systemPromptPart
''';
  }

  /// Gets a random welcome message from the list
  /// Returns null if no welcome messages are defined
  String? getRandomWelcomeMessage() {
    if (welcomeMessages == null || welcomeMessages!.isEmpty) {
      return null;
    }

    // Use current timestamp as seed for randomness to get different messages
    final random =
        (DateTime.now().millisecondsSinceEpoch % welcomeMessages!.length);
    return welcomeMessages![random];
  }
}
