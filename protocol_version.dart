// lib/models/protocol_version.dart

/// The single source of truth for the current version of the Autheet protocol.
///
/// By defining this in a central location, we ensure that all parts of the app
/// (e.g., meeting creation, handshake generation) reference the same version number,
/// making future protocol upgrades and compatibility checks more manageable.
const int autheetProtocolVersion = 1;
