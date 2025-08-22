Loaded cached credentials.
Loaded cached credentials.
Here is a summary of the key differences between the protocol definition and the Dart models:

*   **UserProfile Mismatch**: The `UserProfileModel` in the markdown is implemented as two separate classes, `UserProfilePublic` and `UserProfilePrivate`, in the code. The `hashedPhoneNumber` field specified in the protocol is absent from the implementation. Additionally, the descriptions for `UserProfilePublic` and `UserProfilePrivate` in the markdown are swapped compared to their implementation.

*   **Missing `MeetingBlockModel`**: The `MeetingBlockModel` detailed in the protocol is not present in the Dart code. Instead, there is a `MeetingSigningData` class which differs significantly in its fields, and a `ZkpChainModel` class that is not mentioned in the protocol definition at all.

*   **Incomplete Firestore Serialization**: The `toFirestoreJson` methods for `FindHandshake` and `MeetingModel` in the implementation include several fields that are not documented in the protocol definition, such as versioning, timestamps, and status fields.
