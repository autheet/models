import 'dart:async';

import 'package:autheet/models/ai_models.dart';
import 'package:autheet/models/chat_message.dart';
import 'package:autheet/providers/live_chat_session.dart';
import 'package:autheet/providers/mcp_tools_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart' as ai;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' as toolkit;
import 'package:uuid/uuid.dart';

/// Represents chat metadata with Firestore persistence
/// Wraps firebase_ai.ChatSession via composition
class UserChat {
  final String id;
  final String userId;
  final String title;
  final DateTime createdAt;
  final DateTime? changedAt;
  final AIMode mode;
  final String modelName;
  final List<String> availableTools;
  final bool isLive;

  // The underlying ChatSession (composition, not inheritance)
  ai.ChatSession? _chatSession;

  UserChat({
    required this.id,
    required this.userId,
    required this.title,
    required this.createdAt,
    this.changedAt,
    required this.mode,
    required this.modelName,
    this.availableTools = const [],
    this.isLive = false,
    ai.ChatSession? chatSession,
  }) : _chatSession = chatSession;

  /// Get or create the underlying ChatSession
  ai.ChatSession getChatSession(ai.GenerativeModel model) {
    _chatSession ??= model.startChat();
    return _chatSession!;
  }

  /// Create from Firestore document
  factory UserChat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserChat(
      id: doc.id,
      userId: data['user_id'] as String,
      title: data['chat_title'] as String? ?? 'Untitled',
      createdAt: (data['created_at'] as Timestamp).toDate(),
      changedAt: data['changed_at'] != null
          ? (data['changed_at'] as Timestamp).toDate()
          : null,
      mode: _parseModeFromString(data['mode'] as String?),
      modelName: data['llm_model'] as String? ?? AIMode.standard.modelName,
      availableTools:
          (data['available_tools'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isLive: data['is_live'] as bool? ?? false,
    );
  }

  /// Convert to Firestore document with updated deletion timestamp
  /// This is called whenever the chat metadata is updated (title, mode, etc.)
  Map<String, dynamic> toFirestore() {
    final now = DateTime.now();
    final deletionTime = now.add(const Duration(days: 30));

    return {
      'user_id': userId,
      'chat_title': title,
      'created_at': Timestamp.fromDate(createdAt),
      'changed_at': Timestamp.fromDate(changedAt ?? now),
      'mode': mode.name,
      'llm_model': modelName,
      'available_tools': availableTools,
      'is_live': isLive,
      'server_timestamp': FieldValue.serverTimestamp(),
      'deletion_timestamp': Timestamp.fromDate(
        deletionTime,
      ), // Refreshed on every update
    };
  }

  /// Convert to Firestore for history restoration (without server timestamp sentinel)
  Map<String, dynamic> toHistory() {
    final now = DateTime.now();
    final deletionTime = now.add(const Duration(days: 30));

    return {
      'user_id': userId,
      'chat_title': title,
      'created_at': Timestamp.fromDate(createdAt),
      'changed_at': Timestamp.fromDate(changedAt ?? now),
      'mode': mode.name,
      'llm_model': modelName,
      'available_tools': availableTools,
      'is_live': isLive,
      'server_timestamp': Timestamp.fromDate(
        now,
      ), // Actual timestamp, not sentinel
      'deletion_timestamp': Timestamp.fromDate(deletionTime),
    };
  }

  /// Convert to JSON for UI compatibility
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'mode': mode.name,
      'model': modelName,
    };
  }

  static AIMode _parseModeFromString(String? modeStr) {
    if (modeStr == null) return AIMode.standard;
    return AIMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => AIMode.standard,
    );
  }

  /// Create a copy with updated fields
  UserChat copyWith({
    String? title,
    DateTime? changedAt,
    AIMode? mode,
    String? modelName,
    List<String>? availableTools,
    bool? isLive,
  }) {
    return UserChat(
      id: id,
      userId: userId,
      title: title ?? this.title,
      createdAt: createdAt,
      changedAt: changedAt ?? this.changedAt,
      mode: mode ?? this.mode,
      modelName: modelName ?? this.modelName,
      availableTools: availableTools ?? this.availableTools,
      isLive: isLive ?? this.isLive,
      chatSession: _chatSession,
    );
  }
}

/// Represents a chat settings snapshot stored in subcollection
/// Used to track historical settings when chat configuration changes
class ChatSettings {
  final String chatId;
  final DateTime createdAt;
  final DateTime? deactivatedAt;
  final AIMode mode;
  final List<String> toolList;
  final String? systemPrompt;

  ChatSettings({
    required this.chatId,
    required this.createdAt,
    this.deactivatedAt,
    required this.mode,
    this.toolList = const [],
    this.systemPrompt,
  });

  factory ChatSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatSettings(
      chatId: data['chat_id'] as String,
      createdAt: (data['created_at'] as Timestamp).toDate(),
      deactivatedAt: data['deactivated_at'] != null
          ? (data['deactivated_at'] as Timestamp).toDate()
          : null,
      mode: UserChat._parseModeFromString(data['mode'] as String?),
      toolList:
          (data['tool_list'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      systemPrompt: data['system_prompt'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'chat_id': chatId,
      'created_at': Timestamp.fromDate(createdAt),
      'deactivated_at': deactivatedAt != null
          ? Timestamp.fromDate(deactivatedAt!)
          : null,
      'mode': mode.name,
      'tool_list': toolList,
      'system_prompt': systemPrompt,
    };
  }
}

/// Repository for managing chat sessions and messages
class ChatRepository {
  ChatRepository._({
    required User user,
    required CollectionReference chatsCollection,
    required CollectionReference messagesCollection,
    required List<UserChat> chats,
    required this.mcpToolsProvider,
  }) : _user = user,
       _chatsCollection = chatsCollection,
       _messagesCollection = messagesCollection,
       _chats = ValueNotifier(chats);

  static const newChatTitle = 'Untitled';

  // Manages singleton instances per user ID
  static final Map<String, ChatRepository> _instances = {};

  final User _user;
  final McpToolsProvider mcpToolsProvider;

  /// Retrieves or creates a singleton instance of [ChatRepository] for the given user.
  static ChatRepository? of(User? user, McpToolsProvider mcpToolsProvider) {
    if (user == null || user.uid.isEmpty) {
      return null;
    }

    if (_instances.containsKey(user.uid)) {
      return _instances[user.uid];
    }

    final chatsCollection = FirebaseFirestore.instance.collection(
      'aiuserchats',
    );

    final messagesCollection = FirebaseFirestore.instance.collection(
      'aiuserchat_messages',
    );

    final newInstance = ChatRepository._(
      user: user,
      chatsCollection: chatsCollection,
      messagesCollection: messagesCollection,
      chats: [],
      mcpToolsProvider: mcpToolsProvider,
    );

    _instances[user.uid] = newInstance;
    newInstance._listenForUpdates();

    return newInstance;
  }

  final CollectionReference _chatsCollection;
  final CollectionReference _messagesCollection;
  final ValueNotifier<List<UserChat>> _chats;

  ValueNotifier<List<UserChat>> get chats => _chats;

  StreamSubscription<QuerySnapshot>? _chatsSubscription;

  // Live session management
  final Map<String, LiveChatSession> _liveSessions = {};

  /// Creates a fully configured LlmProvider for a specific chat ID.
  Future<toolkit.LlmProvider> getLlmProvider(
    String chatId, {
    AIMode mode = AIMode.standard,
    String? systemPromptPart,
  }) async {
    debugPrint(
      'ChatRepository: Creating provider for chat $chatId in ${mode.displayName} mode',
    );

    final messages = messagesFor(chatId);
    final history = await messages.history();
    final chat = this[chatId];

    final declarations = mcpToolsProvider.functionDeclarations;
    final hasTools = declarations.isNotEmpty;

    // Build system instruction with optional route context
    String? systemInstruction;
    if (systemPromptPart != null && systemPromptPart.isNotEmpty) {
      systemInstruction =
          '''
You are a helpful AI assistant in the Autheet app.

--- CURRENT SCREEN CONTEXT ---
$systemPromptPart
''';
    }

    // Use latest models for both standard and live modes
    final model =
        ai.FirebaseAI.vertexAI(
          location: 'global',
          appCheck: FirebaseAppCheck.instance,
        ).generativeModel(
          model: mode.modelName,
          tools: hasTools ? [ai.Tool.functionDeclarations(declarations)] : [],
          systemInstruction: systemInstruction != null
              ? ai.Content.system(systemInstruction)
              : null,
        );

    final provider = toolkit.FirebaseProvider(
      model: model,
      history: history,
      onFunctionCall: (functionCall) async {
        final result = await mcpToolsProvider.executeTool(functionCall);
        if (result?.result is Map<String, Object?>) {
          return result!.result;
        }
        return {'result': result?.result};
      },
    );

    provider.addListener(() {
      _saveToolkitHistory(chatId, provider.history.toList());
      debugPrint(
        'ChatRepository: provider listener triggered. History length: ${provider.history.length}, Chat title: ${chat.title}',
      );
      if ((chat.title == newChatTitle || chat.title.isEmpty) &&
          provider.history.isNotEmpty) {
        debugPrint(
          'ChatRepository: Triggering title generation for chat $chatId',
        );
        _generateTitle(chat: chat, provider: provider);
      }
    });

    return provider;
  }

  /// Creates a Live session for real-time audio streaming with transcripts
  Future<LiveChatSession> getLiveSession(String chatId) async {
    debugPrint(
      'ChatRepository: Creating Live session for chat $chatId with user ${_user.uid}',
    );

    // Check if session already exists
    if (_liveSessions.containsKey(chatId) && _liveSessions[chatId]!.isActive) {
      debugPrint('ChatRepository: Reusing existing active session for $chatId');
      return _liveSessions[chatId]!;
    }

    final declarations = mcpToolsProvider.functionDeclarations;
    final hasTools = declarations.isNotEmpty;

    // Configure Live API with transcription
    final config = ai.LiveGenerationConfig(
      speechConfig: ai.SpeechConfig(voiceName: defaultVoiceName),
      responseModalities: [ai.ResponseModalities.audio],
      inputAudioTranscription: ai.AudioTranscriptionConfig(),
      outputAudioTranscription: ai.AudioTranscriptionConfig(),
    );

    final liveModel =
        ai.FirebaseAI.vertexAI(
          location: 'us-central1',
          appCheck: FirebaseAppCheck.instance,
        ).liveGenerativeModel(
          model: AIMode.live.modelName,
          liveGenerationConfig: config,
          // tools: hasTools ? [ai.Tool.functionDeclarations(declarations)] : [],
          tools: [], // Temporarily invalidating tools to debug timeout issues
        );

    debugPrint(
      'ChatRepository: Created Live model with ${hasTools ? declarations.length : 0} tools',
    );

    // Create session with history update callback
    // Create session with history update callback
    final session = LiveChatSession(
      chatId: chatId,
      userId: _user.uid,
      model: liveModel,
      mcpToolsProvider: mcpToolsProvider,
      onHistoryUpdate: (updatedHistory) {
        // Save history updates to Firestore
        _saveLiveHistory(chatId, updatedHistory);
      },
    );

    // Start the session
    await session.start();

    // Store for reuse
    _liveSessions[chatId] = session;

    return session;
  }

  void _listenForUpdates() {
    _chatsSubscription?.cancel();

    _chatsSubscription = _chatsCollection
        .where('user_id', isEqualTo: _user.uid)
        .snapshots()
        .listen((snapshot) {
          final newChats = snapshot.docs
              .map((doc) => UserChat.fromFirestore(doc))
              .toList();
          _chats.value = newChats;
        });
  }

  void dispose() {
    _chatsSubscription?.cancel();

    // Clean up all Live sessions
    for (final session in _liveSessions.values) {
      session.dispose();
    }
    _liveSessions.clear();

    _instances.remove(_user.uid);
  }

  Future<String> createChat({
    AIMode mode = AIMode.standard,
    List<String>? tools,
  }) async {
    final chatId = const Uuid().v4();
    final now = DateTime.now();

    final newChat = UserChat(
      id: chatId,
      userId: _user.uid,
      title: newChatTitle,
      createdAt: now,
      mode: mode,
      modelName: mode.modelName,
      availableTools: tools ?? [],
      isLive: mode.isLive,
    );

    await _chatsCollection.doc(chatId).set(newChat.toFirestore());

    // Create initial settings snapshot in subcollection
    final initialSettings = ChatSettings(
      chatId: chatId,
      createdAt: now,
      mode: mode,
      toolList: tools ?? [],
    );

    await _chatsCollection
        .doc(chatId)
        .collection('settings')
        .add(initialSettings.toFirestore());

    return chatId;
  }

  Future<void> deleteChat(String chatId) async {
    await _chatsCollection.doc(chatId).delete();
    // Also delete all messages for this chat
    final messagesQuery = _messagesCollection.where(
      'chat_id',
      isEqualTo: chatId,
    );
    final messageDocs = await messagesQuery.get();
    for (final doc in messageDocs.docs) {
      await doc.reference.delete();
    }
  }

  /// Updates chat metadata and refreshes deletion_timestamp
  /// If settings changed (mode, tools), archives old settings to subcollection
  Future<void> updateChat(UserChat chat, {UserChat? previousChat}) async {
    // Check if settings changed
    if (previousChat != null &&
        (chat.mode != previousChat.mode ||
            chat.availableTools.toString() !=
                previousChat.availableTools.toString())) {
      // Archive old settings to subcollection
      final oldSettings = ChatSettings(
        chatId: chat.id,
        createdAt: previousChat.changedAt ?? previousChat.createdAt,
        deactivatedAt: DateTime.now(),
        mode: previousChat.mode,
        toolList: previousChat.availableTools,
      );

      await _chatsCollection
          .doc(chat.id)
          .collection('settings')
          .add(oldSettings.toFirestore());

      // Create new settings snapshot
      final newSettings = ChatSettings(
        chatId: chat.id,
        createdAt: DateTime.now(),
        mode: chat.mode,
        toolList: chat.availableTools,
      );

      await _chatsCollection
          .doc(chat.id)
          .collection('settings')
          .add(newSettings.toFirestore());
    }

    // Update root document with refreshed deletion_timestamp
    await _chatsCollection.doc(chat.id).set(chat.toFirestore());
  }

  Future<void> renameChat(String chatId, String newTitle) async {
    final chat = this[chatId];
    final updatedChat = chat.copyWith(
      title: newTitle,
      changedAt: DateTime.now(),
    );
    await updateChat(updatedChat, previousChat: chat);
  }

  UserChat operator [](String id) =>
      _chats.value.firstWhere((chat) => chat.id == id);

  ChatMessageCollection messagesFor(String chatId) => ChatMessageCollection(
    collection: _messagesCollection,
    chatId: chatId,
    userId: _user.uid,
  );

  Future<void> _saveLiveHistory(
    String chatId,
    List<ChatMessage> history,
  ) async {
    final messages = messagesFor(chatId);
    final currentHistory = await messages
        .fetchHistory(); // Get as ChatMessage list
    if (history.length > currentHistory.length) {
      for (var i = currentHistory.length; i < history.length; i++) {
        await messages.addCustom(history[i]);
      }
    }
  }

  Future<void> _saveToolkitHistory(
    String chatId,
    List<toolkit.ChatMessage> history,
  ) async {
    final messages = messagesFor(chatId);
    final currentHistory = await messages.history();
    if (history.length > currentHistory.length) {
      for (var i = currentHistory.length; i < history.length; i++) {
        await messages.add(history[i]);
      }
    }
  }

  Future<void> _generateTitle({
    required UserChat chat,
    required toolkit.LlmProvider provider,
  }) async {
    try {
      final firstMessage = provider.history.first.text ?? '';
      final model =
          ai.FirebaseAI.vertexAI(
            location: 'global',
            appCheck: FirebaseAppCheck.instance,
          ).generativeModel(
            model: AIMode.standard.modelName,
            generationConfig: ai.GenerationConfig(
              temperature: 0.2,
              maxOutputTokens: 20,
            ),
          );

      final prompt =
          'Based on the following user message, create a short, relevant title of 5 words or less for this chat session. Just return the title and nothing else. Message: "$firstMessage"';

      final response = await model.generateContent([ai.Content.text(prompt)]);
      final newTitle = response.text?.trim().replaceAll('"', '');

      if (newTitle != null && newTitle.isNotEmpty) {
        await renameChat(chat.id, newTitle);
      }
    } catch (e, s) {
      debugPrintStack(label: 'Error generating title', stackTrace: s);
    }
  }
}
