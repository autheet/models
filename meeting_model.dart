// lib/models/meeting_model.dart
import 'package:autheet/models/find_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:autheet/models/protocol_version.dart';

// --- Date/Time Utility ---

DateTime? _parseFirestoreTimestamp(dynamic timestamp) {
  if (timestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is Timestamp) {
    return timestamp.toDate();
  }
  return null;
}

// --- Cryptographic Utilities ---

List<String> generateZkpHashChain(String secret) {
  List<String> chain = [];
  List<int> currentBytes = utf8.encode(secret);
  for (var i = 0; i < 100; i++) {
    currentBytes = sha256.convert(currentBytes).bytes;
    chain.add(hex.encode(currentBytes));
  }
  return chain;
}

String generateEncryptionNonce() {
  final random = Random.secure();
  final values = List<int>.generate(12, (i) => random.nextInt(256));
  return base64.encode(values);
}

Future<String> encryptData(
  String jsonData,
  String secret,
  String nonceString,
) async {
  final algorithm = AesGcm.with256bits();
  final secretKey = await algorithm.newSecretKeyFromBytes(
    sha256.convert(utf8.encode(secret)).bytes,
  );
  final nonce = base64.decode(nonceString);
  final secretBox = await algorithm.encrypt(
    utf8.encode(jsonData),
    secretKey: secretKey,
    nonce: nonce,
  );
  return base64.encode(secretBox.concatenation());
}

Future<String> decryptData(
  String encryptedPayload,
  String secret,
  String nonceString,
) async {
  final algorithm = AesGcm.with256bits();
  final secretKey = await algorithm.newSecretKeyFromBytes(
    sha256.convert(utf8.encode(secret)).bytes,
  );
  final encryptedBytes = base64.decode(encryptedPayload);
  final secretBox = SecretBox.fromConcatenation(
    encryptedBytes,
    nonceLength: 12,
    macLength: 16,
  );
  final decryptedBytes = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
  );
  return utf8.decode(decryptedBytes);
}

// --- Enums and Helper Classes ---

enum MeetingStatus {
  clientCreated,
  clientOpen,
  clientClosed,
  signed,
  submitted,
  confirmed,
  stored,
  error,
}

enum SignatureGeneration { client, server }

enum SignatureType { biometric, x509 }

class MeetingEncryptedData {
  final String meetingName;
  final String auHourlyDigest;
  final List<String> participantUids;
  final List<ClientFoundUser> foundUsers;
  final List<MeetingSignature> signatures;

  MeetingEncryptedData({
    required this.meetingName,
    required this.auHourlyDigest,
    this.participantUids = const [],
    this.foundUsers = const [],
    this.signatures = const [],
  });

  MeetingEncryptedData copyWith({
    String? meetingName,
    String? auHourlyDigest,
    List<String>? participantUids,
    List<ClientFoundUser>? foundUsers,
    List<MeetingSignature>? signatures,
  }) {
    return MeetingEncryptedData(
      meetingName: meetingName ?? this.meetingName,
      auHourlyDigest: auHourlyDigest ?? this.auHourlyDigest,
      participantUids: participantUids ?? this.participantUids,
      foundUsers: foundUsers ?? this.foundUsers,
      signatures: signatures ?? this.signatures,
    );
  }

  // This is a client-side convenience model that is part of the encrypted payload.
  // It only needs local serialization methods.
  Map<String, dynamic> toLocalJson() => {
    'meetingName': meetingName,
    'auHourlyDigest': auHourlyDigest,
    'participantUids': participantUids,
    'foundUsers': foundUsers.map((u) => u.toLocalJson()).toList(),
    'signatures': signatures.map((s) => s.toLocalJson()).toList(),
  };

  factory MeetingEncryptedData.fromLocalJson(Map<String, dynamic> json) =>
      MeetingEncryptedData(
        meetingName: json['meetingName'] as String? ?? '',
        auHourlyDigest: json['auHourlyDigest'] as String? ?? '',
        participantUids: List<String>.from(
          json['participantUids'] as List? ?? [],
        ),
        foundUsers: (json['foundUsers'] as List<dynamic>? ?? [])
            .map((j) => ClientFoundUser.fromLocalJson(j))
            .toList(),
        signatures: (json['signatures'] as List<dynamic>? ?? [])
            .map((j) => MeetingSignature.fromLocalJson(j))
            .toList(),
      );
}

class MeetingModel {
  final String id;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime? serverTimestamp;
  final MeetingStatus status;
  final String encryptionNonce;
  final String? encryptedPayload;
  final String hashedMeetingSecret;
  final String meetingName;
  final int participantCount;

  // --- Client-Side Only Data ---
  final String meetingSecret;
  final MeetingEncryptedData? decryptedData;
  final List<FindHandshake> handshakes;

  MeetingModel({
    required this.id,
    required this.createdByUid,
    required this.createdAt,
    this.serverTimestamp,
    required this.status,
    required this.encryptionNonce,
    this.encryptedPayload,
    required this.hashedMeetingSecret,
    required this.meetingName,
    required this.participantCount,
    this.meetingSecret = '',
    this.decryptedData,
    this.handshakes = const [],
  });

  factory MeetingModel.createNew({
    required String creatorUid,
    required String meetingName,
    required String hourlyDigest,
    required List<ClientFoundUser> found,
  }) {
    final secret = sha256
        .convert(utf8.encode(Random.secure().nextDouble().toString()))
        .toString();
    final chain = generateZkpHashChain(secret);
    final participants = [
      creatorUid,
      ...found.map((u) => u.clientDecryptedUid),
    ];

    return MeetingModel(
      id: FirebaseFirestore.instance.collection('temp').doc().id,
      createdByUid: creatorUid,
      createdAt: DateTime.now(),
      status: MeetingStatus.clientCreated,
      encryptionNonce: generateEncryptionNonce(),
      hashedMeetingSecret: chain.last,
      meetingName: meetingName,
      participantCount: participants.length,
      meetingSecret: secret,
      decryptedData: MeetingEncryptedData(
        meetingName: meetingName,
        auHourlyDigest: hourlyDigest,
        participantUids: participants,
        foundUsers: found,
      ),
    );
  }

  factory MeetingModel.fromFirestoreJson(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MeetingModel(
      id: doc.id,
      createdByUid: data['created_by_uid'] ?? '',
      createdAt: _parseFirestoreTimestamp(data['created_at']) ?? DateTime.now(),
      serverTimestamp: _parseFirestoreTimestamp(data['server_timestamp']),
      status: MeetingStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => MeetingStatus.error,
      ),
      encryptionNonce: data['encryption_nonce'] ?? '',
      encryptedPayload: data['encrypted_payload'],
      hashedMeetingSecret: data['hashed_meeting_secret'] ?? '',
      meetingName: data['meetingName'] ?? '',
      participantCount: data['participantCount'] ?? 0,
    );
  }

  Future<Map<String, dynamic>> toFirestoreJson() async {
    if (decryptedData == null) {
      throw StateError("Cannot save to Firestore, decryptedData is null.");
    }

    final payloadJson = json.encode(decryptedData!.toLocalJson());
    final payloadEncrypted = await encryptData(
      payloadJson,
      meetingSecret,
      encryptionNonce,
    );

    return {
      'autheet_protocol_version': autheetProtocolVersion,
      'created_by_uid': createdByUid,
      'created_at': createdAt.millisecondsSinceEpoch,
      'server_timestamp': FieldValue.serverTimestamp(),
      'status': status.name,
      'encryption_nonce': encryptionNonce,
      'hashed_meeting_secret': hashedMeetingSecret,
      'meetingName': decryptedData!.meetingName,
      'participantCount': decryptedData!.participantUids.length,
      'encrypted_payload': payloadEncrypted,
    };
  }

  Future<MeetingModel> decrypt(String clientSecret) async {
    if (encryptedPayload == null) return this;
    try {
      final decryptedJson = await decryptData(
        encryptedPayload!,
        clientSecret,
        encryptionNonce,
      );
      final data = MeetingEncryptedData.fromLocalJson(
        json.decode(decryptedJson),
      );
      return copyWith(decryptedData: data, meetingSecret: clientSecret);
    } catch (e) {
      print("Failed to decrypt meeting payload: $e");
      return this;
    }
  }

  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'createdByUid': createdByUid,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'serverTimestamp': serverTimestamp?.millisecondsSinceEpoch,
      'status': status.name,
      'encryptionNonce': encryptionNonce,
      'encryptedPayload': encryptedPayload,
      'hashedMeetingSecret': hashedMeetingSecret,
      'meetingName': meetingName,
      'participantCount': participantCount,
      'meetingSecret': meetingSecret,
      'decryptedData': decryptedData?.toLocalJson(),
      'handshakes': handshakes.map((h) => h.toLocalJson()).toList(),
    };
  }

  factory MeetingModel.fromLocalJson(Map<String, dynamic> json) {
    return MeetingModel(
      id: json['id'],
      createdByUid: json['createdByUid'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      serverTimestamp: json['serverTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['serverTimestamp'])
          : null,
      status: MeetingStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MeetingStatus.error,
      ),
      encryptionNonce: json['encryptionNonce'],
      encryptedPayload: json['encryptedPayload'],
      hashedMeetingSecret: json['hashedMeetingSecret'],
      meetingName: json['meetingName'] ?? '',
      participantCount: json['participantCount'] ?? 0,
      meetingSecret: json['meetingSecret'],
      decryptedData: json['decryptedData'] != null
          ? MeetingEncryptedData.fromLocalJson(json['decryptedData'])
          : null,
      handshakes: (json['handshakes'] as List<dynamic>? ?? [])
          .map((h) => FindHandshake.fromLocalJson(h))
          .toList(),
    );
  }

  MeetingModel copyWith({
    String? id,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? serverTimestamp,
    MeetingStatus? status,
    String? encryptionNonce,
    String? encryptedPayload,
    String? hashedMeetingSecret,
    String? meetingName,
    int? participantCount,
    String? meetingSecret,
    MeetingEncryptedData? decryptedData,
    List<FindHandshake>? handshakes,
  }) {
    return MeetingModel(
      id: id ?? this.id,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      status: status ?? this.status,
      encryptionNonce: encryptionNonce ?? this.encryptionNonce,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      hashedMeetingSecret: hashedMeetingSecret ?? this.hashedMeetingSecret,
      meetingName: meetingName ?? this.meetingName,
      participantCount: participantCount ?? this.participantCount,
      meetingSecret: meetingSecret ?? this.meetingSecret,
      decryptedData: decryptedData ?? this.decryptedData,
      handshakes: handshakes ?? this.handshakes,
    );
  }
}

class MeetingSignature {
  final String signature;
  final String signedBy;
  final String publicKeyId;
  final SignatureGeneration generation;
  final SignatureType type;
  final DateTime createdAt;
  final String signedDataHash;
  final Map<String, dynamic> signedData;

  MeetingSignature({
    required this.signature,
    required this.signedBy,
    required this.publicKeyId,
    required this.generation,
    required this.type,
    required this.createdAt,
    required this.signedData,
  }) : signedDataHash = sha256
           .convert(utf8.encode(json.encode(signedData)))
           .toString();

  Map<String, dynamic> toFirestoreJson() => {
    'signature': signature,
    'signed_by': signedBy,
    'public_key_id': publicKeyId,
    'generation': generation.name,
    'type': type.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'signed_data_hash': signedDataHash,
  };

  factory MeetingSignature.fromFirestoreJson(Map<String, dynamic> json) {
    return MeetingSignature(
      signature: json['signature'] ?? '',
      signedBy: json['signed_by'] ?? '',
      publicKeyId: json['public_key_id'] ?? '',
      generation: SignatureGeneration.values.firstWhere(
        (e) => e.name == json['generation'],
        orElse: () => SignatureGeneration.client,
      ),
      type: SignatureType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SignatureType.biometric,
      ),
      createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
      signedData: {},
    );
  }

  Map<String, dynamic> toLocalJson() => {
    'signature': signature,
    'signed_by': signedBy,
    'public_key_id': publicKeyId,
    'generation': generation.name,
    'type': type.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'signed_data_hash': signedDataHash,
    'signed_data': signedData,
  };

  factory MeetingSignature.fromLocalJson(Map<String, dynamic> json) =>
      MeetingSignature(
        signature: json['signature'] ?? '',
        signedBy: json['signed_by'] ?? '',
        publicKeyId: json['public_key_id'] ?? '',
        generation: SignatureGeneration.values.firstWhere(
          (e) => e.name == json['generation'],
          orElse: () => SignatureGeneration.client,
        ),
        type: SignatureType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => SignatureType.biometric,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at']),
        signedData: Map<String, dynamic>.from(json['signed_data'] ?? {}),
      );
}
