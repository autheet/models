import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' as toolkit;

/// Message type enum for different message sources
enum MessageType { user, llm, tool, toolCall, toolList, system }

extension MessageTypeExtension on MessageType {
  String get name {
    switch (this) {
      case MessageType.user:
        return 'user';
      case MessageType.llm:
        return 'llm';
      case MessageType.tool:
        return 'tool';
      case MessageType.toolCall:
        return 'tool_call';
      case MessageType.toolList:
        return 'tool_list';
      case MessageType.system:
        return 'system';
    }
  }

  static MessageType fromString(String type) {
    switch (type) {
      case 'user':
        return MessageType.user;
      case 'llm':
        return MessageType.llm;
      case 'tool':
        return MessageType.tool;
      case 'tool_call':
        return MessageType.toolCall;
      case 'tool_list':
        return MessageType.toolList;
      case 'system':
        return MessageType.system;
      default:
        return MessageType.user;
    }
  }
}

/// Represents a single chat message with metadata
/// Messages are IMMUTABLE - they are never updated, only created or deleted
class ChatMessage {
  final String id;
  final String chatId;
  final String userId;
  final MessageType type;
  final String? text;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;
  final DateTime deletionTimestamp;
  final bool visible;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.type,
    this.text,
    this.metadata,
    required this.timestamp,
    required this.deletionTimestamp,
    this.visible = true,
  });

  /// Create from Firestore document
  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      chatId: data['chat_id'] as String,
      userId: data['user_id'] as String,
      type: MessageTypeExtension.fromString(data['type'] as String? ?? 'user'),
      text: data['text'] as String?,
      metadata: data['metadata'] as Map<String, dynamic>?,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      deletionTimestamp: (data['deletion_timestamp'] as Timestamp).toDate(),
      visible: data['visible'] as bool? ?? true,
    );
  }

  /// Convert to Firestore document for initial creation ONLY
  /// Messages are immutable - this should only be called once when creating
  Map<String, dynamic> toFirestore() {
    return {
      'chat_id': chatId,
      'user_id': userId,
      'type': type.name,
      'text': text,
      'metadata': metadata,
      'timestamp': Timestamp.fromDate(timestamp),
      'deletion_timestamp': Timestamp.fromDate(deletionTimestamp),
      'visible': visible,
      'server_timestamp': FieldValue.serverTimestamp(),
    };
  }

  /// Convert to Firestore for history restoration (without server timestamp sentinel)
  Map<String, dynamic> toHistory() {
    return {
      'chat_id': chatId,
      'user_id': userId,
      'type': type.name,
      'text': text,
      'metadata': metadata,
      'timestamp': Timestamp.fromDate(timestamp),
      'deletion_timestamp': Timestamp.fromDate(deletionTimestamp),
      'visible': visible,
      'server_timestamp': Timestamp.fromDate(
        DateTime.now(),
      ), // Actual timestamp, not sentinel
    };
  }

  /// Convert to toolkit.ChatMessage for LLM provider compatibility
  toolkit.ChatMessage toToolkitMessage() {
    // Reconstruct the original toolkit message from metadata if available
    if (metadata != null && metadata!.containsKey('original_json')) {
      return toolkit.ChatMessage.fromJson(
        metadata!['original_json'] as Map<String, dynamic>,
      );
    }

    // Otherwise create a simple text message based on type
    final origin = type == MessageType.user
        ? toolkit.MessageOrigin.user
        : toolkit.MessageOrigin.llm;

    return toolkit.ChatMessage(
      origin: origin,
      text: text ?? '',
      attachments: const [],
    );
  }

  /// Create from toolkit.ChatMessage
  /// Automatically detects message type and can hide tool-related messages
  static ChatMessage fromToolkitMessage({
    required String chatId,
    required String userId,
    required toolkit.ChatMessage message,
    MessageType? messageType,
    bool? visible,
  }) {
    // Determine message type from toolkit message
    MessageType type = messageType ?? _inferMessageType(message);

    // Auto-hide tool calls and tool responses by default (can be overridden)
    bool shouldBeVisible = visible ?? _shouldBeVisible(type);

    final now = DateTime.now();
    final deletionTime = now.add(const Duration(days: 30));

    return ChatMessage(
      id: '', // Will be set by Firestore
      chatId: chatId,
      userId: userId,
      type: type,
      text: message.text,
      metadata: {
        'original_json': message.toJson(),
        'origin': message.origin.toString(),
      },
      timestamp: now,
      deletionTimestamp: deletionTime,
      visible: shouldBeVisible,
    );
  }

  /// Infer message type from toolkit.ChatMessage
  static MessageType _inferMessageType(toolkit.ChatMessage message) {
    // Check origin first
    if (message.origin == toolkit.MessageOrigin.user) {
      return MessageType.user;
    } else if (message.origin == toolkit.MessageOrigin.llm) {
      return MessageType.llm;
    }

    // Check message content for tool-related data
    final json = message.toJson();

    // Check for function calls (tool calls from LLM)
    if (json.containsKey('functionCalls') ||
        json.containsKey('function_calls')) {
      return MessageType.toolCall;
    }

    // Check for function responses (tool results)
    if (json.containsKey('functionResponses') ||
        json.containsKey('function_responses')) {
      return MessageType.tool;
    }

    // Default to LLM for non-user messages
    return MessageType.llm;
  }

  /// Determine if message should be visible by default based on type
  static bool _shouldBeVisible(MessageType type) {
    switch (type) {
      case MessageType.user:
      case MessageType.llm:
        return true; // Always show user and LLM messages
      case MessageType.toolCall:
      case MessageType.tool:
      case MessageType.toolList:
        return false; // Hide tool-related messages by default
      case MessageType.system:
        return false; // Hide system messages by default
    }
  }

  /// Create a copy with updated fields
  /// Note: This creates a NEW message, it doesn't update the existing one
  ChatMessage copyWith({
    String? text,
    Map<String, dynamic>? metadata,
    bool? visible,
  }) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      userId: userId,
      type: type,
      text: text ?? this.text,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp,
      deletionTimestamp: deletionTimestamp,
      visible: visible ?? this.visible,
    );
  }
}

/// A collection of messages for a specific chat with Firestore listeners
class ChatMessageCollection {
  ChatMessageCollection({
    required CollectionReference collection,
    required this.chatId,
    required this.userId,
  }) : _collection = collection {
    _initializeListeners();
  }

  final CollectionReference _collection;
  final String chatId;
  final String userId;

  // Stream controllers for real-time updates
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final _toolkitMessagesController =
      StreamController<List<toolkit.ChatMessage>>.broadcast();

  StreamSubscription<QuerySnapshot>? _messagesSubscription;

  /// Initialize Firestore listeners
  /// Fetches ALL messages (including hidden) for proper LLM context
  void _initializeListeners() {
    _messagesSubscription = _collection
        .where('chat_id', isEqualTo: chatId)
        .where('user_id', isEqualTo: userId)
        .orderBy('timestamp')
        .snapshots()
        .listen((snapshot) {
          final allMessages = snapshot.docs
              .map((doc) => ChatMessage.fromFirestore(doc))
              .toList();

          // Emit all messages (including hidden) for LLM context
          _messagesController.add(allMessages);

          // Emit all messages as toolkit messages (LLM needs hidden tool calls/results)
          _toolkitMessagesController.add(
            allMessages.map((msg) => msg.toToolkitMessage()).toList(),
          );
        });
  }

  /// A stream of ALL ChatMessage objects from Firestore (including hidden)
  /// This is important for maintaining proper LLM context with tool calls
  Stream<List<ChatMessage>> get stream => _messagesController.stream;

  /// A stream of ALL toolkit.ChatMessage objects for LLM provider compatibility
  /// Includes hidden messages (tool calls, tool results) needed for context
  Stream<List<toolkit.ChatMessage>> get toolkitStream =>
      _toolkitMessagesController.stream;

  /// A stream of ONLY VISIBLE messages for UI display
  /// Use this for chat UI to hide tool execution details
  Stream<List<ChatMessage>> get visibleStream =>
      stream.map((messages) => messages.where((msg) => msg.visible).toList());

  /// A stream of ONLY VISIBLE toolkit messages for UI display
  Stream<List<toolkit.ChatMessage>> get visibleToolkitStream => stream.map(
    (messages) => messages
        .where((msg) => msg.visible)
        .map((msg) => msg.toToolkitMessage())
        .toList(),
  );

  /// Fetches the entire chat history once from Firestore as ChatMessage objects
  /// Returns ALL messages (including hidden) for proper LLM context
  Future<List<ChatMessage>> fetchHistory() async {
    final snapshot = await _collection
        .where('chat_id', isEqualTo: chatId)
        .where('user_id', isEqualTo: userId)
        .orderBy('timestamp')
        .get();
    return snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList();
  }

  /// Fetches the chat history as toolkit.ChatMessage objects for LLM provider
  /// Returns ALL messages (including hidden tool calls/results) for proper context
  Future<List<toolkit.ChatMessage>> history() async {
    final messages = await fetchHistory();
    return messages.map((msg) => msg.toToolkitMessage()).toList();
  }

  /// Adds a new toolkit.ChatMessage to Firestore
  /// Messages are immutable - this creates a new document
  Future<String> add(toolkit.ChatMessage message) async {
    final chatMessage = ChatMessage.fromToolkitMessage(
      chatId: chatId,
      userId: userId,
      message: message,
    );

    final doc = await _collection.add(chatMessage.toFirestore());
    return doc.id;
  }

  /// Adds a custom ChatMessage to Firestore
  /// Messages are immutable - this creates a new document
  Future<String> addCustom(ChatMessage message) async {
    final doc = await _collection.add(message.toFirestore());
    return doc.id;
  }

  /// Soft-deletes a message by setting visible to false
  /// Useful for hiding tool calls, tool responses, and system messages
  Future<void> hideMessage(String messageId) async {
    await _collection.doc(messageId).update({'visible': false});
  }

  /// Shows a previously hidden message by setting visible to true
  /// Useful for debugging or showing tool execution details
  Future<void> showMessage(String messageId) async {
    await _collection.doc(messageId).update({'visible': true});
  }

  /// Hard-deletes a message (sets deletion timestamp to now for immediate TTL)
  Future<void> deleteMessage(String messageId) async {
    await _collection.doc(messageId).update({
      'deletion_timestamp': Timestamp.now(),
      'visible': false,
    });
  }

  /// Bulk add messages from history (useful for migration or restoration)
  /// Uses toHistory() to avoid server timestamp sentinel
  Future<void> addBulk(List<toolkit.ChatMessage> messages) async {
    final batch = FirebaseFirestore.instance.batch();

    for (final message in messages) {
      final chatMessage = ChatMessage.fromToolkitMessage(
        chatId: chatId,
        userId: userId,
        message: message,
      );
      final docRef = _collection.doc();
      batch.set(
        docRef,
        chatMessage.toHistory(),
      ); // Use toHistory() for restoration
    }

    await batch.commit();
  }

  /// Dispose of listeners
  void dispose() {
    _messagesSubscription?.cancel();
    _messagesController.close();
    _toolkitMessagesController.close();
  }
}
