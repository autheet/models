# Autheet Protocol Definition

This document outlines the core data models and their interactions within the Autheet system.

## Introduction to Autheet

Autheet is a privacy-preserving authentication and verifiable event logging application. Its core purpose is to allow users to securely identify and verify the presence of other users in a physical proximity, and to create a tamper-evident record of these interactions (referred to as "meetings").

A unique aspect of Autheet's approach is the derivation and sharing of common secrets (referred to as `clientPattern`s) from environmental measurements and device interactions. Instead of exchanging pre-shared keys or relying solely on a centralized server for discovery, Autheet leverages various finding technologies to generate a shared secret between nearby devices simultaneously. These technologies include:

*   **Shaking**: Analyzing synchronized device movement patterns.
*   **Bluetooth**: Utilizing Bluetooth signal characteristics or ephemeral identifiers.
*   **UWB (Ultra-Wideband)**: Employing precise UWB ranging data.
*   **NFC (Near Field Communication)**: Facilitating close-proximity key exchange.

These environmental measurements are processed client-side to derive a temporary, shared `clientPattern`. This pattern is never directly transmitted or stored in a publicly accessible location like Firestore.

To add another layer of security and unpredictability that is independent of Autheet's operators, the app incorporates a time-based public value called the `auHourlyDigest`. This digest is derived from an external, publicly verifiable source that updates regularly, such as the Bitcoin blockchain's block height. By incorporating `auHourlyDigest` into cryptographic operations, Autheet ensures that certain time-sensitive secrets or identifiers change in a way that cannot be predicted or manipulated by the Autheet service itself.

The sharing of information that relies on the `auHourlyDigest` (such as encrypted payloads in the handshake) is restricted to devices that have been approved by **Firebase App Check**. App Check helps verify that incoming traffic to Firebase services originates from your genuine app, mitigating abuse and ensuring that only legitimate instances of the Autheet application can participate in the secure discovery process.

The following sections detail the data models that support this architecture and the protocols governing their use.

---

## Application Architecture and Initialization


## Model Serialization Strategy

A core principle of the Autheet architecture is the strict separation of data intended for remote storage (Firestore) versus local caching (SharedPreferences). This separation is crucial for security, privacy, and performance. To enforce this, every persistent data model implements a clear set of serialization methods.

### The Two Persistence Targets

1.  **Firestore (Remote Storage)**:
    *   **Purpose**: The single source of truth, accessible by the user from different devices.
    *   **Characteristics**: Must handle server-side operations. Critically, it must **never** store unencrypted Personally Identifiable Information (PII) or client-side secrets.
    *   **Methods**: `toFirestoreJson()` and `fromFirestoreJson()`.

2.  **Local Cache (Local Storage)**:
    *   **Purpose**: A fast, local copy of the data for immediate UI rendering and offline access.
    *   **Characteristics**: Data must be fully self-contained and restorable. It can safely contain decrypted data and client secrets as it resides in the app's secure storage on the user's device.
    *   **Methods**: `toLocalJson()` and `fromLocalJson()`.

---

## Model-by-Model Breakdown

---

## Application Architecture and Initialization

This section outlines the initial setup and core architectural components that are initialized when the Autheet app starts, as seen in `lib/main.dart`.

### Firebase Initialization and Configuration

The application leverages Firebase services extensively. The initialization process sets up the necessary connections and configurations.

*   **`Firebase.initializeApp`**: This is the first step, initializing Firebase with platform-specific options provided by `DefaultFirebaseOptions.currentPlatform`.

*   **Firestore Persistence**:
    *   For web, in-memory persistence is enabled using `FirebaseFirestore.instance.enablePersistence(const PersistenceSettings(synchronizeTabs: true))`. This caches data for the current session.
    *   For mobile platforms (Android and iOS), persistent disk caching is enabled by default, but it's explicitly configured using `FirebaseFirestore.instance.settings` with `persistenceEnabled: true` and `cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED` for offline capabilities.

*   **Firebase App Check**: App Check is activated to help ensure that requests to Firebase services are coming from your legitimate app.
    *   **Web**: Uses `ReCaptchaV3Provider` with a configured site key.
    *   **Android**: Uses `AndroidProvider.playIntegrity` in release mode and `AndroidProvider.debug` in debug mode.
    *   **Apple (iOS and macOS)**: Uses `AppleProvider.appAttest` in release mode and `AppleProvider.debug` in debug mode.

*   **Firebase Analytics and Crashlytics**: These services are configured based on user privacy settings managed by the `SettingsService`. Data collection is enabled or disabled accordingly using `FirebaseAnalytics.instance.setAnalyticsCollectionEnabled()` and `FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled()`. Flutter errors are also routed to Crashlytics using `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError`.

### Service Instances and Initialization

Several core service instances are created and initialized during the application startup. These services encapsulate specific functionalities.

*   **`DatabaseService`**: Likely handles interactions with local databases or storage mechanisms.
*   **`NTPService`**: Manages Network Time Protocol synchronization, crucial for time-sensitive operations within the app. It is initialized with the `DatabaseService`.
*   **`SettingsService`**: Loads and manages application settings, including privacy preferences for analytics and crash reporting.
*   **`UserSessionProvider`**: Manages the current user's session information and authentication state.
*   **`NotificationService`**: Handles displaying notifications to the user.
*   **`FirebaseFunctions`**: Provides an interface for interacting with Firebase Cloud Functions, specifically configured for the `europe-west1` region.

These services are initialized asynchronously using `Future.wait()` to ensure they are ready before the main application UI is built.

### Provider Usage for State Management and Dependency Injection

The application uses the `provider` package for state management and dependency injection.

*   **`MultiProvider`**: In `lib/main.dart`, `MultiProvider` is used to make instances of the initialized services and other providers available throughout the widget tree.
*   **Making Services Available**: Instances of `DatabaseService`, `NTPService`, `SettingsService`, `FirebaseFunctions`, `UserSessionProvider`, `NotificationService`, and `FirebaseFirestore` are provided using `Provider.value`.
*   **ChangeNotifier Providers**: `NTPService`, `SettingsService`, `UserSessionProvider`, and `NfcProvider` are exposed as `ChangeNotifierProvider`s, allowing widgets to react to changes in their state.
*   **Dependency Injection**: This pattern allows widgets and other parts of the application to access necessary services and data without needing to create instances themselves, promoting modularity and testability. For example, the `AutheetApp` widget receives the `NTPService` directly.

This provider setup ensures that essential services and shared state are easily accessible to the parts of the application that need them.

---

## Model-by-Model Breakdown

The following section details the individual data models used within the Autheet application.


### `PublicKey`

Stores a user's public key information.

*   #### `toFirestoreJson()`
    *   **Purpose**: Prepare the object for saving to the `/public_keys` collection in Firestore.
    *   **Action**: Creates a map containing only the `key`, `clientName`, `usage_count`, and `hashed_user_id`. It uses `FieldValue.serverTimestamp()` to let Firestore's servers assign the creation time, preventing client-side clock manipulation.
    *   **PII Note**: The cleartext `userId` is never stored. The `publicKeyId` serves as the document ID and is not part of the document body.

*   #### `fromFirestoreJson(Map<String, dynamic> json, String docId, ...)`
    *   **Purpose**: Reconstruct a `PublicKey` object from a Firestore document snapshot.
    *   **Action**: Populates the model using the document data (`json`) and the document's ID (`docId`), which becomes the `publicKeyId`. The `userId` must be supplied from the app's current session context.

*   #### `toLocalJson()`
    *   **Purpose**: Prepare the object for caching in local storage.
    *   **Action**: Creates a fully self-contained JSON string. It includes the `publicKeyId` and the cleartext `userId`. It converts the Firestore `Timestamp` object into a simple integer (`millisecondsSinceEpoch`) for easy serialization.

*   #### `fromLocalJson(Map<String, dynamic> json)`
    *   **Purpose**: Reconstruct a `PublicKey` object from the local cache.
    *   **Action**: Rebuilds the object from the map. As a security check, it re-calculates the `publicKeyId` from the `key` to ensure data integrity.

*   #### `usage_count` (New Field Explanation)
    *   **Purpose**: This field tracks the number of times a specific public key has been used to sign a transaction (e.g., a meeting).
    *   **Security Implications**: Monitoring the `usage_count` is crucial for security. A key that is used an unexpectedly high number of times could indicate a compromised device or a misuse of the key. It also provides a basis for implementing key rotation policies, where users are prompted to generate a new key after a certain number of uses, limiting the "attack surface" of any single key.

### `UserProfileModel`

*   **Firestore Storage (`toFirestoreJson`)**: Stores `uid`, `displayName`, `email`, `photoUrl`, and `hashedPhoneNumber`.
*   **Local Storage (`toLocalJson`)**: Caches the same data as Firestore for offline access.
*   **Data Separation & Hashing**:
    *   The model follows the standard pattern of separating remote and local concerns.
    *   The `hashedPhoneNumber` is a critical privacy feature. The user's raw phone number is never stored remotely. The hash is a one-way cryptographic function (e.g., SHA-256).
*   **ZKP Potential**:
    *   This provides a "proof-of-knowledge." A user can prove they know a specific phone number by hashing it and comparing it to the `hashedPhoneNumber` on record. This can be done without revealing the number itself to a third party who doesn't already possess it. This is a basic but effective form of privacy preservation.

### `NtpLog`

*   **Firestore Storage**: This model is **not stored in Firestore**.
*   **Local Storage (`toLocalJson` / `fromLocalJson`)**: The entire object is saved to the local device database (e.g., via `DatabaseService`). This includes the NTP server, timestamps, time offset, and any errors.
*   **Purpose**: This is purely a diagnostic and debugging model. It helps analyze the reliability and performance of time synchronization, which is critical for other protocols that rely on coordinated time. It has no PII and no ZKP applicability.

### `FindHandshake`

The core model for the privacy-preserving discovery mechanism. The serialization methods are critical for security.

*   #### `toFirestoreJson()`
    *   **Purpose**: Prepare the handshake for posting to the public `/handshakes` collection.
    *   **Action**: Creates a map containing only the public, non-reversible hashes (`argon_pattern`, `argon_userid`) and the `encrypted_payload`.
    *   **CRITICAL PII NOTE**: This method **intentionally omits** the `clientPattern`. The `clientPattern` is the shared secret and must never be sent to Firestore. This is the cornerstone of the handshake's privacy model.

*   #### `fromFirestoreJson(Map<String, dynamic> json)`
    *   **Purpose**: Reconstruct a `FindHandshake` from a document in the `/handshakes` collection.
    *   **Action**: Populates the model from the Firestore data. The `clientPattern` field will always be empty, as it is not stored remotely.

*   #### `toLocalJson()`
    *   **Purpose**: Save a complete, functional handshake object to the local cache, typically as part of a `MeetingModel`.
    *   **Action**: Serializes the *entire* object, including the sensitive `clientPattern`, so that it can be fully reconstructed for decryption purposes later.

*   #### `fromLocalJson(Map<String, dynamic> json)`
    *   **Purpose**: Reconstruct a complete `FindHandshake` from the local cache.
    *   **Action**: Rebuilds the object with all its fields, including the `clientPattern`.

### `MeetingModel`

Represents a single meeting event.

*   #### `toFirestoreJson()`
    *   **Purpose**: Save the meeting state to the `/meetings` collection.
    *   **Action**:
        1.  Encrypts the `decryptedData` object into the `encrypted_payload` string.
        2.  Saves the `meetingName` and `participantCount` as top-level, unencrypted fields for easy access in list views without needing to decrypt the payload.
        3.  Uses `FieldValue.serverTimestamp()`.
    *   **PII Note**: All sensitive details (participant UIDs, etc.) are inside the encrypted payload. Only the creator's UID is stored in plain text.

*   #### `fromFirestoreJson(DocumentSnapshot doc)`
    *   **Purpose**: Reconstruct a `MeetingModel` from a Firestore document.
    *   **Action**: Populates the model with the unencrypted fields. The `decryptedData` field will be `null`. To access the encrypted information, the `decrypt()` method must be called separately after retrieving the appropriate `meetingSecret`.

*   #### `toLocalJson()`
    *   **Purpose**: Cache the entire state of a meeting locally.
    *   **Action**: Serializes the entire object, including the `meetingSecret`, the full `decryptedData` object (if available), and any associated `FindHandshake` objects.

*   #### `fromLocalJson(Map<String, dynamic> json)`
    *   **Purpose**: Reconstruct a complete `MeetingModel` from the local cache.
    *   **Action**: Rebuilds the entire object, allowing the UI to immediately display all meeting details without needing to decrypt or fetch additional data.

### `MeetingBlockModel` & `MeetingSigningData`

These models represent a "block" in a user-specific blockchain for a meeting, creating a tamper-evident log.

*   **Firestore Storage (`toFirestoreJson`)**: Stores the core components of the block: `blockId`, `meetingId`, `publicKeyId`, the digital `signature`, the `previousBlockHash`, and the `signedData` itself.
*   **Local Storage (`toLocalJson`)**: Caches the full block data for quick access and verification on the client.
*   **Data Separation & Hashing**:
    *   **`previousBlockHash`**: This is a hash of the previous block in the sequence. This creates a cryptographic chain where changing any past block would invalidate the entire chain, making tampering obvious.
    *   **`signature`**: This is a digital signature of the block's `signedData`, proving that the owner of the `publicKeyId` attested to the data at a specific time.
    *   **`hashedParticipantUids` (in `MeetingSigningData`)**: To protect privacy, the list of participants is stored as a list of hashes, not raw user IDs. These hashes are computed with the private `meetingSecret`.
*   **ZKP Potential**:
    *   The combination of these features provides a powerful **proof of integrity**. Anyone can verify the entire history of a meeting by checking the hash chain and the digital signatures on each block.
    *   Furthermore, because the participant list is hashed with the `meetingSecret`, the meeting creator can **prove a user was present** without revealing the full list of other participants to that user. They can do this by revealing the secret used to hash that specific user's ID. This is a powerful, practical application of zero-knowledge principles.

### Client-Only & Encapsulated Models

These models do not have Firestore serialization methods because they are never stored directly in Firestore collections.

*   **`ClientFoundUser`**: Exists only in memory and within the local cache as part of other objects. It only has `toLocalJson()` and `fromLocalJson()`.
*   **`MeetingEncryptedData`**: Represents the structure of the data *inside* the `encrypted_payload` of a `MeetingModel`. It is never stored unencrypted in Firestore and therefore only has `toLocalJson()` and `fromLocalJson()`.
*   **`MeetingSignature`**: While the signature *is* stored in a Firestore subcollection, its `signedData` field contains a JSON representation of the `MeetingSigningData`. The model has `toFirestoreJson()` to save the signature metadata and `toLocalJson()` to be part of the cached `MeetingModel`.

This disciplined approach to serialization ensures data is handled consistently and securely throughout the application, respecting user privacy while providing robust functionality.

---
## Detailed Model Concepts and Zero-Knowledge Proofs

This section provides a deeper dive into the purpose of each data model and how they work together to create a secure and private system.

### The Handshake Protocol: Privacy-Preserving Discovery

The primary challenge in discovering nearby users is to do so without revealing one's identity to everyone. The handshake protocol solves this using a combination of shared secrets and cryptographic hashing.

*   **`PatternCryptor`**: This is a cryptographic utility class, not a data model. It's the engine for the handshake. Given a temporary shared secret (`clientPattern`) and a time-based public value (`auHourlyDigest`), it can encrypt and decrypt payloads.

*   **`FindHandshake`**: This is the central model of the discovery process.
    *   **Usage**: When two users want to connect, their devices generate a temporary, identical `clientPattern` (e.g., based on BLE nonces or a sound they both heard).
    *   **ZKP Aspect**: Instead of revealing the `clientPattern`, the app computes a non-reversible hash of it (`argonPattern`). This hash is public and is posted to Firestore. Since both users started with the same secret, they will generate the same public hash. They can then query Firestore for this public hash to find each other's handshake documents. An attacker who only sees the public hash cannot reverse it to find the original secret `clientPattern`.
    *   **Payload Encryption**: The `FindHandshake` also contains a payload with the user's actual ID and meeting information. This payload is encrypted using a key derived from the secret `clientPattern`. Only the other user who knows the *exact* same `clientPattern` can derive the key and decrypt the payload. To anyone else, the payload is indecipherable noise.

*   **`ClientFoundUser`**: This is a simple, in-memory data model that holds the *decrypted* information of a user found via a successful handshake. It is the result of a successful `PatternCryptor.decrypt()` call and is never persisted to Firestore directly.

### The Meeting and Signing Protocol: Verifiable Events

Once participants are identified, the focus shifts to creating a verifiable and tamper-proof record of the meeting.

*   **`MeetingModel`**: This is the main container for a meeting event.
    *   **Core Data**: It holds essential metadata like the meeting name, the creator's ID, and the participant count.
    *   **Encryption**: All sensitive details—including the list of participant UIDs and the raw handshake data—are stored in the `encryptedPayload`. This payload is encrypted with a unique `meetingSecret` that is known only to the meeting's creator (and potentially shared with participants in a future version). This ensures that even if the Firestore database is compromised, the full details of the meeting remain confidential.

*   **`MeetingEncryptedData`**: This is not a top-level model but rather defines the *structure* of the data that gets encrypted inside the `MeetingModel.encryptedPayload`.

*   **`ZkpChainModel` & The Meeting Secret**:
    *   **`meetingSecret`**: When a `MeetingModel` is created, it also generates a random, high-entropy `meetingSecret`.
    *   **`generateZkpHashChain`**: This function creates a Zero-Knowledge Proof hash chain from the `meetingSecret`. It repeatedly hashes the secret (e.g., 100 times).
    *   **ZKP Aspect**: The final hash in the chain (`hashedMeetingSecret`) is stored publicly in the `MeetingModel`. The original `meetingSecret` is kept private on the client. To prove they know the secret at a later time (e.g., to authorize a change), the client can reveal the *previous* hash in the chain. The server can verify this by hashing it one time to see if it matches the public `hashedMeetingSecret`. This proves knowledge of the secret without ever revealing the secret itself.

*   **`MeetingSigningData`**: This model represents the "block" in a user-specific blockchain for meetings.
    *   **Purpose**: It creates a definitive, immutable snapshot of the meeting's participants and details at the moment of signing.
    *   **Hashing**: It creates a `signableHash` by combining all critical meeting data (participant hashes, meeting secret hash, and the hash of the *previous* meeting block) into a single string and hashing it. This chaining of blocks makes the history tamper-evident. Any change to a past block would invalidate the hashes of all subsequent blocks.
    *   **PII Protection**: Note that it does not contain raw UIDs. Instead, it uses `hashedParticipantUids`, which are derived using the private `meetingSecret`. This means the list of participants is pseudonymized and only someone with the `meetingSecret` can verify who was part of the meeting.

*   **`MeetingSignature`**: This is the final proof.
    *   **Content**: It contains the digital signature (from the user's device key) of the `signableHash` from the `MeetingSigningData`.
    *   **Verifiability**: This proves that a specific user, identified by their `publicKeyId`, attests to the exact state of the meeting as captured in the `MeetingSigningData` at a specific point in time. It is the final, undeniable link between a user and a meeting event.

---
## Meeting and Recognition Lifecycle

This new section outlines the sequence of events from creating a meeting to signing it.

1.  **Initiation**: A user navigates to the "Create Meeting" screen. A new, empty `MeetingModel` is created in the `MeetingRecognitionProvider` with a `draft` status. A unique `meetingId` and `meetingSecret` are generated.

2.  **Discovery Activation**: The user activates one or more finding technologies (e.g., Bluetooth, NFC, Sound). The app begins broadcasting and scanning for discovery patterns related to the active `meetingId`.

3.  **Participant Recognition**:
    *   When another user's device is detected, a secure handshake occurs using the `FindHandshake` protocol.
    *   Upon successful decryption of a handshake payload, a `ClientFoundUser` object is created and added to a list of found participants within the provider.
    *   The UI updates to show the number of participants found.

4.  **Preparation for Signing**:
    *   Once the user is satisfied with the list of participants, they proceed to the signing screen.
    *   The meeting status is changed to `pending_signature`.
    *   A `MeetingSigningData` block is generated, creating an immutable `signableHash` of the current participant list and meeting details.

5.  **Biometric Signing**:
    *   The user is prompted for their biometric authentication (e.g., Face ID, fingerprint).
    *   Upon success, the `SigningService` uses the hardware-backed private key to create a digital `MeetingSignature` of the `signableHash`.
    *   The `usage_count` for the user's public key is incremented.

6.  **Storage and Completion**:
    *   The `MeetingModel`, the `MeetingSigningData` block, and the resulting `MeetingSignature` are all written to Firestore.
    *   The meeting status is updated to `stored`, indicating it is complete and cryptographically sealed.

---
## Missing Protocol and Model Definitions

This section identifies areas where the current models and protocol definition are incomplete, pointing to future work.

1.  **Meeting Secret Sharing Mechanism**:
    *   **The Gap**: Currently, the `meetingSecret` is generated and held exclusively by the meeting creator. This is sufficient for the creator to decrypt their own meeting records. However, the protocol does not define a secure method for sharing this `meetingSecret` with the other participants.
    *   **The Implication**: Without the `meetingSecret`, other participants cannot decrypt the `encryptedPayload` of the `MeetingModel`. This means they cannot independently verify the full list of participants or other sensitive meeting details from the Firestore record. This is a critical missing piece for multi-party verification.

2.  **Absence of Certificate Models**:
    *   **The Gap**: The current system relies on a "Trust on First Use" (TOFU) model for public keys, which are stored raw in Firestore. The protocol and models lack any structure for handling a Public Key Infrastructure (PKI).
    *   **Missing Models**: There are no models for:
        *   **Certificate Signing Request (CSR)**: A formal structure that a client would generate to request a certificate from a Certificate Authority (CA).
        *   **X.509 Certificate**: The standard model for a digital certificate that binds a public key to an identity, signed by a trusted CA.
    *   **The Implication**: Without a PKI, verifying a user's key relies solely on trusting the integrity of the Firestore database. A formal PKI would add a stronger, more standardized layer of trust and verification, allowing for features like key revocation and a clear chain of trust.

3.  **Formal Revocation Process**:
    *   **The Gap**: While the `PublicKey` model could be updated with a "status" field, the protocol does not define a formal process for key revocation.
    *   **The Implication**: If a user loses their device, there is no defined protocol for them to revoke their old key and issue a new one, nor is there a defined way for other clients to be notified of this revocation (e.g., via a Certificate Revocation List or OCSP).