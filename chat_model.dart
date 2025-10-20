import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  Chat({
    required this.id,
    required this.title,
    DateTime? deletionTimestamp,
  }) : deletion_timestamp =
            deletionTimestamp ?? DateTime.now().add(const Duration(days: 30));

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      title: json['title'] as String,
      deletionTimestamp: (json['deletion_timestamp'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String title;
  final DateTime deletion_timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'deletion_timestamp': Timestamp.fromDate(deletion_timestamp),
      };
}
