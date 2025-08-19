// lib/models/public_key_model.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user's public key, designed for storage in Firestore and local caching.
class PublicKey {
  /// The SHA-256 hash of the public key, used as the document ID in Firestore.
  final String publicKeyId;
  
  /// A privacy-preserving hash of the user's UID and the publicKeyId.
  final String hashedUserId;

  /// The public key string, typically in a standard format like Base64.
  final String key;
  
  /// A server-side timestamp of when the key was stored.
  final Timestamp? serverTimestamp;
  
  /// The number of times this key has been used to sign a meeting.
  final int usageCount;

  /// The cleartext UID of the owner. This is used for local operations and
  /// is *never* stored in Firestore.
  final String userId;
  
  /// A friendly name for the key, set by the client (e.g., "Pixel 8 Pro").
  /// This helps the user identify their keys in a list.
  final String? clientName;

  PublicKey({
    required this.userId,
    required this.key,
    this.serverTimestamp,
    this.usageCount = 0,
    this.clientName,
  }) : publicKeyId = sha256.convert(utf8.encode(key)).toString(),
       hashedUserId = sha256.convert(utf8.encode(userId + sha256.convert(utf8.encode(key)).toString())).toString();

  /// Private constructor for internal use by factories and copyWith.
  PublicKey._({
    required this.publicKeyId,
    required this.hashedUserId,
    required this.key,
    required this.serverTimestamp,
    required this.usageCount,
    required this.userId,
    this.clientName,
  });
  
  PublicKey copyWith({
    String? publicKeyId,
    String? hashedUserId,
    String? key,
    Timestamp? serverTimestamp,
    int? usageCount,
    String? userId,
    String? clientName,
  }) {
    return PublicKey._(
      publicKeyId: publicKeyId ?? this.publicKeyId,
      hashedUserId: hashedUserId ?? this.hashedUserId,
      key: key ?? this.key,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      usageCount: usageCount ?? this.usageCount,
      userId: userId ?? this.userId,
      clientName: clientName ?? this.clientName,
    );
  }

  /// Converts the [PublicKey] instance into a Map suitable for Firestore serialization.
  Map<String, dynamic> toFirestoreJson() {
    return {
      'hashed_user_id': hashedUserId,
      'key': key,
      'server_timestamp': FieldValue.serverTimestamp(),
      'usage_count': usageCount,
      'client_name': clientName,
    };
  }
  
  Map<String, dynamic> toLocalJson() {
    return {
      'publicKeyId': publicKeyId,
      'hashed_user_id': hashedUserId,
      'key': key,
      'server_timestamp': serverTimestamp?.millisecondsSinceEpoch,
      'usage_count': usageCount,
      'userId': userId,
      'client_name': clientName,
    };
  }

  /// Creates a [PublicKey] instance from a Firestore document snapshot.
  factory PublicKey.fromFirestoreJson(Map<String, dynamic> json, String docId, {required String userId}) {
    return PublicKey._(
      publicKeyId: docId,
      key: json['key'] ?? '',
      userId: userId,
      hashedUserId: json['hashed_user_id'] ?? '',
      serverTimestamp: json['server_timestamp'] as Timestamp?,
      usageCount: json['usage_count'] as int? ?? 0,
      clientName: json['client_name'] as String?,
    );
  }

  factory PublicKey.fromLocalJson(Map<String, dynamic> json) {
    final key = json['key'] as String? ?? '';
    final userId = json['userId'] as String? ?? '';
    final calculatedPublicKeyId = sha256.convert(utf8.encode(key)).toString();

    if (calculatedPublicKeyId != json['publicKeyId']) {
      throw const FormatException("Public key ID does not match the key content.");
    }
    
    return PublicKey._(
      publicKeyId: json['publicKeyId'] as String,
      key: key,
      userId: userId,
      hashedUserId: json['hashed_user_id'] as String? ?? '',
      serverTimestamp: json['server_timestamp'] != null
          ? Timestamp.fromMillisecondsSinceEpoch(json['server_timestamp'])
          : null,
      usageCount: json['usage_count'] as int? ?? 0,
      clientName: json['client_name'] as String?,
    );
  }
}
