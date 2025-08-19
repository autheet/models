// lib/models/meeting_block_model.dart
import 'package:autheet/models/meeting_model.dart';
import 'package:autheet/models/protocol_version.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:convert/convert.dart';

// --- Date/Time Utility ---

DateTime? _parseFirestoreTimestamp(dynamic timestamp) {
  if (timestamp is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is Timestamp) {
    return timestamp.toDate();
  }
  return null;
}

/// A dedicated data structure that holds the exact, pseudonymized data used to create the signature hash.
/// This is stored in the `meetings/{meetingId}/meeting_data/{userId}` subcollection.
class MeetingSigningData {
  final String meetingId;
  final List<String> hashedParticipantUids;
  final List<String> hashedOtherUsersMeetingIds;
  final String hashedMeetingSecret;
  final String previousBlockHash;
  final DateTime createdAt;
  final DateTime? serverTimestamp;

  MeetingSigningData({
    required this.meetingId,
    required this.hashedParticipantUids,
    required this.hashedOtherUsersMeetingIds,
    required this.hashedMeetingSecret,
    required this.previousBlockHash,
    DateTime? createdAt,
    this.serverTimestamp,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Creates the definitive hash of the block's data, which is what gets digitally signed.
  /// The order of concatenation is critical for reproducibility.
  String get signableHash {
    final sortedHashedUids = List<String>.from(hashedParticipantUids)..sort();
    final sortedHashedOtherMeetingIds = List<String>.from(
      hashedOtherUsersMeetingIds,
    )..sort();

    final blockContent =
        '$meetingId${sortedHashedUids.join()}${sortedHashedOtherMeetingIds.join()}$hashedMeetingSecret$previousBlockHash';
    return sha256.convert(utf8.encode(blockContent)).toString();
  }

  factory MeetingSigningData.fromMeetingModel(
    MeetingModel meeting,
    String previousBlockHash,
  ) {
    if (meeting.decryptedData == null) {
      throw StateError(
        "Cannot create signing data from a meeting that has not been decrypted.",
      );
    }

    String secureHash(String value) {
      List<int> currentBytes = utf8.encode(value + meeting.meetingSecret);
      for (var i = 0; i < 100; i++) {
        currentBytes = sha256.convert(currentBytes).bytes;
      }
      return hex.encode(currentBytes);
    }

    final hashedParticipantUids = meeting.decryptedData!.participantUids
        .map((uid) => secureHash(uid))
        .toList();

    final hashedOtherUsersMeetingIds = meeting.decryptedData!.foundUsers
        .where((user) => user.clientDecryptedUid != meeting.createdByUid)
        .map((user) => secureHash(user.clientDecryptedMeetingId))
        .toList();

    return MeetingSigningData(
      meetingId: meeting.id,
      hashedParticipantUids: hashedParticipantUids,
      hashedOtherUsersMeetingIds: hashedOtherUsersMeetingIds,
      hashedMeetingSecret: meeting.hashedMeetingSecret,
      previousBlockHash: previousBlockHash,
    );
  }

  Map<String, dynamic> toFirestoreJson() => {
    'meeting_id': meetingId,
    'hashed_participant_uids': hashedParticipantUids,
    'hashed_other_users_meeting_ids': hashedOtherUsersMeetingIds,
    'hashed_meeting_secret': hashedMeetingSecret,
    'previous_block_hash': previousBlockHash,
    'created_at': createdAt.millisecondsSinceEpoch,
    'server_timestamp': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> toLocalJson() => {
    'meeting_id': meetingId,
    'hashed_participant_uids': hashedParticipantUids,
    'hashed_other_users_meeting_ids': hashedOtherUsersMeetingIds,
    'hashed_meeting_secret': hashedMeetingSecret,
    'previous_block_hash': previousBlockHash,
    'created_at': createdAt.millisecondsSinceEpoch,
    'server_timestamp': serverTimestamp?.millisecondsSinceEpoch,
  };
  
  factory MeetingSigningData.fromFirestoreJson(Map<String, dynamic> json) =>
    MeetingSigningData(
      meetingId: json['meeting_id'] ?? '',
      hashedParticipantUids: List<String>.from(
        json['hashed_participant_uids'] as List? ?? [],
      ),
      hashedOtherUsersMeetingIds: List<String>.from(
        json['hashed_other_users_meeting_ids'] as List? ?? [],
      ),
      hashedMeetingSecret: json['hashed_meeting_secret'] ?? '',
      previousBlockHash: json['previous_block_hash'] ?? '',
      createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
      serverTimestamp: _parseFirestoreTimestamp(json['server_timestamp']),
    );

  factory MeetingSigningData.fromLocalJson(Map<String, dynamic> json) =>
      MeetingSigningData(
        meetingId: json['meeting_id'] ?? '',
        hashedParticipantUids: List<String>.from(
          json['hashed_participant_uids'] as List? ?? [],
        ),
        hashedOtherUsersMeetingIds: List<String>.from(
          json['hashed_other_users_meeting_ids'] as List? ?? [],
        ),
        hashedMeetingSecret: json['hashed_meeting_secret'] ?? '',
        previousBlockHash: json['previous_block_hash'] ?? '',
        createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
        serverTimestamp: _parseFirestoreTimestamp(json['server_timestamp']),
      );
}

/// Represents the ZKP chain data stored in the `meeting_blocks` collection.
class ZkpChainModel {
  final String meetingId;
  final String hashedMeetingSecret;
  final List<String> zkpChain;
  final DateTime createdAt;
  final DateTime? serverTimestamp;

  ZkpChainModel({
    required this.meetingId,
    required this.hashedMeetingSecret,
    required this.zkpChain,
    DateTime? createdAt,
    this.serverTimestamp,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestoreJson() => {
    'autheet_protocol_version': autheetProtocolVersion,
    'meeting_id': meetingId,
    'hashed_meeting_secret': hashedMeetingSecret,
    'zkp_chain': zkpChain,
    'created_at': createdAt.millisecondsSinceEpoch,
    'server_timestamp': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> toLocalJson() => {
    'autheet_protocol_version': autheetProtocolVersion,
    'meeting_id': meetingId,
    'hashed_meeting_secret': hashedMeetingSecret,
    'zkp_chain': zkpChain,
    'created_at': createdAt.millisecondsSinceEpoch,
    'server_timestamp': serverTimestamp?.millisecondsSinceEpoch,
  };

  factory ZkpChainModel.fromFirestoreJson(Map<String, dynamic> json) =>
      ZkpChainModel(
        meetingId: json['meeting_id'] as String? ?? '',
        hashedMeetingSecret: json['hashed_meeting_secret'] as String? ?? '',
        zkpChain: List<String>.from(json['zkp_chain'] as List? ?? []),
        createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
        serverTimestamp: _parseFirestoreTimestamp(json['server_timestamp']),
      );
      
  factory ZkpChainModel.fromLocalJson(Map<String, dynamic> json) =>
      ZkpChainModel(
        meetingId: json['meeting_id'] as String? ?? '',
        hashedMeetingSecret: json['hashed_meeting_secret'] as String? ?? '',
        zkpChain: List<String>.from(json['zkp_chain'] as List? ?? []),
        createdAt: _parseFirestoreTimestamp(json['created_at']) ?? DateTime.now(),
        serverTimestamp: _parseFirestoreTimestamp(json['server_timestamp']),
      );
}
