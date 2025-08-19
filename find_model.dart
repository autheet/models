// lib/models/find_model.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autheet/models/finding_technology.dart';
import 'package:cryptography/cryptography.dart';
import 'package:autheet/functions/crypto_worker.dart';
import 'package:flutter/foundation.dart';
// Use a prefix to prevent name collisions with class members.
import 'package:autheet/models/protocol_version.dart' as pv;


DateTime? _parseFirestoreTimestamp(dynamic timestamp) {
  if (timestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is Timestamp) {
    return timestamp.toDate();
  }
  return null;
}

// --- Cryptographic Helper ---

/// A dedicated cryptographic helper class for the handshake process.
/// It encapsulates the logic for deriving keys and encrypting/decrypting payloads.
///
/// EFFICIENCY UPGRADE: This class now caches the results of expensive cryptographic
/// operations (Argon2 hashes and key derivations). Once a value is computed, it is
/// stored and returned instantly on subsequent calls, dramatically reducing the
/// CPU load for each handshake.
class PatternCryptor {
  final String clientPattern;
  final String auHourlyDigest;

  // --- Internal Cache ---
  SecretKey? _cachedSecretKey;
  String? _cachedArgonPattern;

  PatternCryptor({required this.clientPattern, required this.auHourlyDigest});

  /// Returns the secret key, deriving it only on the first call.
  Future<SecretKey> getSecretKey() async {
    if (_cachedSecretKey != null) return _cachedSecretKey!;
    
    _cachedSecretKey = await compute(computeArgonForEncryptionKey, ArgonDerivationParams(
      password: clientPattern,
      nonce: auHourlyDigest,
    ));
    return _cachedSecretKey!;
  }

  /// Returns the public pattern hash, computing it only on the first call.
  Future<String> getArgonPattern() async {
    if (_cachedArgonPattern != null) return _cachedArgonPattern!;

    _cachedArgonPattern = await compute(computeArgonForPattern, ArgonDerivationParams(
      password: clientPattern,
      nonce: auHourlyDigest,
    ));
    return _cachedArgonPattern!;
  }

  /// Encrypts the payload using the (now cached) secret key.
  Future<String> encrypt(String plaintext) async {
    final secretKey = await getSecretKey();
    return await compute(computeAesGcmEncrypt, AesGcmEncryptParams(
      secretKey: secretKey,
      plaintext: plaintext,
    ));
  }

  /// Decrypts the payload using the (now cached) secret key.
  Future<String?> decrypt(String encryptedPayload) async {
    final secretKey = await getSecretKey();
    return await compute(computeAesGcmDecrypt, AesGcmDecryptParams(
      secretKey: secretKey,
      encodedCiphertext: encryptedPayload,
    ));
  }
}


/// Represents a user found during the meeting recognition process.
/// This model contains the decrypted, cleartext information about the other user.
/// It is intended for client-side use only and should not be stored directly in Firestore.
class ClientFoundUser {
  final String clientDecryptedUid;
  final String clientDecryptedEmail;
  final String clientDecryptedMeetingId;
  final String findingTechnology;

  ClientFoundUser({
    required this.clientDecryptedUid,
    required this.clientDecryptedEmail,
    required this.clientDecryptedMeetingId,
    required this.findingTechnology,
  });

  // This model is client-only, so it only needs methods for local serialization.
  Map<String, dynamic> toLocalJson() => {
    'clientDecryptedUid': clientDecryptedUid,
    'clientDecryptedEmail': clientDecryptedEmail,
    'clientDecryptedMeetingId': clientDecryptedMeetingId,
    'findingTechnology': findingTechnology,
  };

  factory ClientFoundUser.fromLocalJson(Map<String, dynamic> json) => ClientFoundUser(
    clientDecryptedUid: json['clientDecryptedUid'] ?? '',
    clientDecryptedEmail: json['clientDecryptedEmail'] ?? '',
    clientDecryptedMeetingId: json['clientDecryptedMeetingId'] ?? '',
    findingTechnology: json['findingTechnology'] ?? '',
  );
}


/// Represents a handshake document stored in the `handshakes` collection in Firestore.
/// This model carefully separates data to ensure PII (Personally Identifiable Information)
/// like the `clientPattern` is never sent to the server.
class FindHandshake {
  // --- Client-Side Only Data ---
  /// Contains PII (e.g., user's nonce + other user's nonce).
  /// This value is CRITICAL and MUST NEVER be sent to Firestore.
  /// It is used exclusively on the client to derive the decryption key.
  final String clientPattern;

  /// The hourly digest used to create this handshake.
  /// This value is CRITICAL and MUST NEVER be sent to Firestore.
  /// It ensures the correct key is derived for decryption, even if the hour changes.
  final String auHourlyDigest;

  // --- Firestore-Stored Data ---
  /// A public, non-reversible hash of the `clientPattern`.
  /// Used to find matching patterns in Firestore without revealing the pattern itself.
  final String argonPattern;
  
  /// A public, non-reversible hash of the user's UID.
  /// Used to prevent a user from matching with their own handshake documents.
  final String argonUserId;
  
  /// The encrypted payload containing the `ClientFoundUser` data.
  /// Can only be decrypted by a user who has the same `clientPattern`.
  final String encryptedPayload;
  
  /// The specific technology (e.g., BLE, Sound) that generated this handshake.
  /// This is crucial for analytics and debugging to understand which methods are
  /// most effective and to diagnose technology-specific issues.
  final TechnologyType technologyType;

  /// The version of the handshake protocol used to create this document.
  /// This is essential for backward compatibility if the protocol is ever updated.
  final int autheetProtocolVersion;

  final DateTime createdAt;
  final DateTime? serverTimestamp;

  // The constructor requires the protocol version.
  FindHandshake({
    required this.clientPattern,
    required this.auHourlyDigest,
    required this.argonPattern,
    required this.argonUserId,
    required this.encryptedPayload,
    required this.technologyType,
    required this.autheetProtocolVersion,
    DateTime? createdAt,
    this.serverTimestamp,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// Factory to create a new handshake instance.
  /// This is the primary and safest way to create a handshake, as it enforces
  /// the entire security model (hashing, encryption, PII separation).
  static Future<FindHandshake> create({
    required String userId,
    required String meetingId,
    required String email,
    required PatternCryptor cryptor,
    required TechnologyType technologyType,
  }) async {
    
    // 1. Get the public pattern hash from the cryptor (now cached).
    final argonPattern = await cryptor.getArgonPattern();
    
    // 2. Create a public, non-reversible hash of the user's ID.
    // This is still computed separately as it doesn't depend on the clientPattern.
    final argonUserId = await compute(computeArgonForUserId, ArgonDerivationParams(
      password: userId,
      nonce: cryptor.auHourlyDigest,
    ));
    
    // 3. Create the payload with the user's actual information.
    final payload = ClientFoundUser(
      clientDecryptedUid: userId,
      clientDecryptedEmail: email,
      clientDecryptedMeetingId: meetingId,
      findingTechnology: technologyType.name,
    );
    
    // 4. Encrypt the payload using the cryptor (which uses its cached key).
    final encryptedPayload = await cryptor.encrypt(jsonEncode(payload.toLocalJson()));
    
    // 5. Return the fully constructed handshake object.
    // The handshake is stamped with the current protocol version from the single
    // source of truth and now includes the digest it was created with.
    return FindHandshake(
      clientPattern: cryptor.clientPattern,
      auHourlyDigest: cryptor.auHourlyDigest, // <-- FIX: Store the digest used.
      argonPattern: argonPattern,
      argonUserId: argonUserId,
      encryptedPayload: encryptedPayload,
      technologyType: technologyType,
      autheetProtocolVersion: pv.autheetProtocolVersion,
    );
  }


  /// Creates a representation of the handshake suitable for storing in Firestore.
  /// Note the intentional omission of `clientPattern` and `auHourlyDigest` to protect PII.
  Map<String, dynamic> toFirestoreJson() => {
    'argon_pattern': argonPattern,
    'argon_userid': argonUserId,
    'encrypted_payload': encryptedPayload,
    'technology_type': technologyType.name, // Stored as a string for easy querying.
    'autheet_protocol_version': autheetProtocolVersion,
    'created_at': createdAt.millisecondsSinceEpoch,
    'server_timestamp': FieldValue.serverTimestamp(),
  };
  
  /// Creates a representation of the handshake suitable for local caching.
  /// Includes all data needed to fully reconstruct the object.
  Map<String, dynamic> toLocalJson() => {
    'client_pattern': clientPattern,
    'au_hourly_digest': auHourlyDigest,
    'argon_pattern': argonPattern,
    'argon_userid': argonUserId,
    'encrypted_payload': encryptedPayload,
    'technology_type': technologyType.name,
    'autheet_protocol_version': autheetProtocolVersion,
    'created_at': createdAt.millisecondsSinceEpoch,
    'server_timestamp': serverTimestamp?.millisecondsSinceEpoch,
  };

  /// Creates a [FindHandshake] instance from a Firestore document.
  /// Note: `clientPattern` and `auHourlyDigest` cannot be recovered from Firestore
  /// data and will be empty. This object is not suitable for decryption.
  factory FindHandshake.fromFirestoreJson(Map<String, dynamic> json) {
    return FindHandshake(
      clientPattern: '', // Is not and should not be stored in Firestore.
      auHourlyDigest: '', // Is not and should not be stored in Firestore.
      argonPattern: json['argon_pattern'] ?? '',
      argonUserId: json['argon_userid'] ?? '',
      encryptedPayload: json['encrypted_payload'] ?? '',
      technologyType: TechnologyType.values.byName(json['technology_type'] ?? 'unknown'),
      // Read the original protocol version from the document.
      // If it's missing, fall back to the current version.
      autheetProtocolVersion: json['autheet_protocol_version'] ?? pv.autheetProtocolVersion,
      createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
      serverTimestamp: _parseFirestoreTimestamp(json['server_timestamp']),
    );
  }

  /// Creates a [FindHandshake] instance from a local JSON map.
  factory FindHandshake.fromLocalJson(Map<String, dynamic> json) {
    return FindHandshake(
      clientPattern: json['client_pattern'] ?? '',
      auHourlyDigest: json['au_hourly_digest'] ?? '',
      argonPattern: json['argon_pattern'] ?? '',
      argonUserId: json['argon_userid'] ?? '',
      encryptedPayload: json['encrypted_payload'] ?? '',
      technologyType: TechnologyType.values.byName(json['technology_type'] ?? 'unknown'),
      // Read the original protocol version from the document.
      // If it's missing, fall back to the current version.
      autheetProtocolVersion: json['autheet_protocol_version'] ?? pv.autheetProtocolVersion,
      createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
      serverTimestamp: _parseFirestoreTimestamp(json['server_timestamp']),
    );
  }
}
