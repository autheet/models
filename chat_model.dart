import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' as toolkit;

/// A class representing a chat session.
class Chat {
  Chat({required this.id, required this.title});

  final String id;
  final String title;

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Chat(id: doc.id, title: data['title'] as String? ?? 'Untitled');
  }

  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

/// A collection of messages in a chat, using the toolkit's ChatMessage.
class MessageCollection {
  MessageCollection({required CollectionReference collection})
    : _collection = collection;

  final CollectionReference _collection;

  /// A stream of `ChatMessage` objects from Firestore.
  Stream<List<toolkit.ChatMessage>> get stream => _collection
      .orderBy('timestamp')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => toolkit.ChatMessage.fromJson(
                doc.data() as Map<String, dynamic>,
              ),
            )
            .toList(),
      );

  /// Fetches the entire chat history once from Firestore.
  Future<List<toolkit.ChatMessage>> history() async {
    final snapshot = await _collection.orderBy('timestamp').get();
    return snapshot.docs
        .map(
          (doc) =>
              toolkit.ChatMessage.fromJson(doc.data() as Map<String, dynamic>),
        )
        .toList();
  }

  /// Adds a new `ChatMessage` to Firestore.
  Future<String> add(toolkit.ChatMessage message) async {
    final doc = await _collection.add({
      ...message.toJson(),
      'timestamp': FieldValue.serverTimestamp(),
      'deletionTimestamp': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      ),
    });
    return doc.id;
  }
}
