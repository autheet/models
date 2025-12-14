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
  live,

  /// Speech-to-text transcription using gemini-2.5-flash
  /// Used specifically for transcribing voice messages
  speechToText,
}

extension AIModeExtension on AIMode {
  String get displayName {
    switch (this) {
      case AIMode.standard:
        return 'Text Chat';
      case AIMode.live:
        return 'Live Audio';
      case AIMode.speechToText:
        return 'Speech to Text';
    }
  }

  String get modelName {
    switch (this) {
      case AIMode.standard:
        return 'gemini-2.5-flash';
      case AIMode.live:
        return "gemini-live-2.5-flash-preview-native-audio-09-2025"; //'gemini-live-2.5-flash'; //live models list  https://firebase.google.com/docs/ai-logic/live-api?api=vertex#before-you-begin
      case AIMode.speechToText:
        return 'gemini-2.5-flash';
    }
  }

  bool get isLive => this == AIMode.live;
}

/// Default voice name for Live API
const String defaultVoiceName = 'Puck';

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
  final List<SuggestionPrompt>? suggestions;

  /// Optional welcome messages to display in the chat UI for this route
  /// A random message from this list will be shown to the user
  final List<String>? welcomeMessages;

  /// Optional list of allowed MCP tool names (or prefixes) for Standard Mode
  /// If null, defaults to ALL tools.
  final List<String>? allowedTools;

  /// Optional list of allowed MCP tool names (or prefixes) for Live Mode
  /// If null, defaults to a RESTRICTED set (navigation only).
  final List<String>? allowedLiveTools;

  const AIRouteContext({
    required this.path,
    this.systemPromptPart,
    required this.description,
    this.suggestions,
    this.welcomeMessages,
    this.allowedTools,
    this.allowedLiveTools,
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

/// Represents a suggested prompt that can be displayed to the user
class SuggestionPrompt {
  /// The label to display in the UI (e.g. "Summarize")
  final String label;

  /// The actual prompt text to send to the AI (e.g. "Please summarize the current context")
  final String prompt;

  const SuggestionPrompt({required this.label, required this.prompt});
}
