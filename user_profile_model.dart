// lib/models/user_profile_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:autheet/models/find_model.dart';
import 'package:autheet/models/protocol_version.dart';

/// Data model for another user's public profile information.
class UserProfilePublic {
  final String uid;
  final String? displayName;
  final String? bio;
  final String? email; // Populated from a subcollection

  UserProfilePublic({
    required this.uid,
    this.displayName,
    this.bio,
    this.email,
  });

  factory UserProfilePublic.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return UserProfilePublic(
      uid: doc.id,
      displayName: data['display_name'],
      bio: data['bio'],
    );
  }

  /// Creates a map representation of the public profile, suitable for writing to Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'display_name': displayName,
      'bio': bio,
      'autheet_protocol_version': autheetProtocolVersion,
    };
  }

  UserProfilePublic copyWith({
    String? displayName,
    String? bio,
    String? email,
  }) {
    return UserProfilePublic(
      uid: uid,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      email: email ?? this.email,
    );
  }
}

/// Data model for the current user's private settings.
class UserProfilePrivate {
  final String uid;
  final String? email;
  final UserSettings settings;
  final String? autheetDeviceName;

  UserProfilePrivate({
    required this.uid,
    this.email,
    required this.settings,
    this.autheetDeviceName,
  });

  factory UserProfilePrivate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return UserProfilePrivate(
      uid: doc.id,
      email: data['email'],
      settings: UserSettings.fromMap(data['settings']),
      autheetDeviceName: data['autheet_device_name'],
    );
  }

  /// Creates a map representation of the private profile, suitable for writing to Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'settings': {
        'public_profile': settings.publicProfile,
        'make_email_resolvable': settings.makeEmailResolvable,
        'share_email_found': settings.shareEmailFound,
      },
      'autheet_device_name': autheetDeviceName,
      'autheet_protocol_version': autheetProtocolVersion,
    };
  }
}

/// Represents the user's configurable privacy and app settings.
class UserSettings {
  final bool publicProfile;
  final bool makeEmailResolvable;
  final bool shareEmailFound;

  UserSettings({
    this.publicProfile = false,
    this.makeEmailResolvable = false,
    this.shareEmailFound = false,
  });

  factory UserSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return UserSettings();
    return UserSettings(
      publicProfile: map['public_profile'] ?? false,
      makeEmailResolvable: map['make_email_resolvable'] ?? false,
      shareEmailFound: map['share_email_found'] ?? false,
    );
  }
}
