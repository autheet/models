// lib/models/protocol_version.dart

/// The single source of truth for the current version of the Autheet protocol.
///
/// By defining this in a central location, we ensure that all parts of the app
/// (e.g., meeting creation, handshake generation) reference the same version number,
/// making future protocol upgrades and compatibility checks more manageable.
const int autheetProtocolVersion = 1;

/// A flag indicating if the draft implementation status for the current protocol version is enabled.
/// Set to `true` during development of a new version, `false` for stable releases.
const bool autheetProtocolVersionImplementationStatusDraft = true;

/// The path to the Markdown file containing the Autheet Protocol Definition relative to the lib/models directory.
/// This is used by the protocol compliance test.
const String autheetProtocolDefinitionPath = 'lib/models/Autheet Protocol Definition.md';

/// The URL to the Markdown file containing the Autheet Protocol Definition.
/// This is used by the protocol compliance test if the other is not found.
const String autheetProtocolDefinitionUrl =
    'https://github.com/autheet/models/blob/main/Autheet%20Protocol%20Definition.md';
