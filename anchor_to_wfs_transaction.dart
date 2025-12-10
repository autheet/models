/// Represents a transaction request to convert an AR Anchor into a WFS Feature.
/// This model captures all necessary geospatial and AR data to be passed to an LLM/MCP tool.
class AnchorToWfsTransaction {
  /// Unique identifier for the anchor (from AR session)
  final String anchorId;

  /// The type of anchor (e.g., 'plane', 'cloud', 'geospatial', 'rooftop')
  final String anchorType;

  /// Semantic label if available (e.g., 'wall', 'floor', 'table')
  final String? semanticLabel;

  /// Geospatial Latitude (decimal degrees)
  final double? latitude;

  /// Geospatial Longitude (decimal degrees)
  final double? longitude;

  /// Altitude in meters (WGS84 ellipsoid usually, or relative)
  final double? altitude;

  /// Compass or Geospatial Heading (degrees, 0 = North, clockwise)
  final double? heading;

  /// Accuracy of the geospatial pose (if available)
  final double? accuracy;

  /// The 4x4 transformation matrix of the anchor in local world space.
  /// Stored as a flat list of 16 doubles (column-major).
  final List<double> transformationMatrix;

  /// Timestamp when this anchor was captured/created
  final DateTime timestamp;

  /// Any additional metadata the user wants to attach (e.g., 'Color: Red', 'Type: Bench')
  final Map<String, dynamic> metadata;

  AnchorToWfsTransaction({
    required this.anchorId,
    required this.anchorType,
    this.semanticLabel,
    this.latitude,
    this.longitude,
    this.altitude,
    this.heading,
    this.accuracy,
    required this.transformationMatrix,
    required this.timestamp,
    this.metadata = const {},
  });

  /// Converts the model to a JSON map for serialization.
  Map<String, dynamic> toJson() {
    return {
      'anchorId': anchorId,
      'anchorType': anchorType,
      'semanticLabel': semanticLabel,
      'geospatial': {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'heading': heading,
        'accuracy': accuracy,
      },
      'transformationMatrix': transformationMatrix,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Creates an instance from a JSON map.
  factory AnchorToWfsTransaction.fromJson(Map<String, dynamic> json) {
    return AnchorToWfsTransaction(
      anchorId: json['anchorId'] as String,
      anchorType: json['anchorType'] as String,
      semanticLabel: json['semanticLabel'] as String?,
      latitude: (json['geospatial']?['latitude'] as num?)?.toDouble(),
      longitude: (json['geospatial']?['longitude'] as num?)?.toDouble(),
      altitude: (json['geospatial']?['altitude'] as num?)?.toDouble(),
      heading: (json['geospatial']?['heading'] as num?)?.toDouble(),
      accuracy: (json['geospatial']?['accuracy'] as num?)?.toDouble(),
      transformationMatrix: (json['transformationMatrix'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  // --- NEXT STEPS ---
  // 1. Integrate this model into `ArWfsTWidget`.
  // 2. When an anchor is placed (e.g., `_onPlaneOrPointTapped`), populate this model:
  //    - `transformationMatrix` from `ARAnchor.transformation.storage`.
  //    - `geospatial` fields from `ARStateProvider` (current device pose) OR
  //      if using Geospatial Anchors, directly from the anchor's geospatial data.
  // 3. Create a logic flow (e.g., a Provider method or direct LLM call) to serialize this object
  //    to JSON and send it as a prompt/context to the LLM.
  //    Example Prompt: "I have placed a new object. Here is the data: <JSON_STRING>. Please add this to the WFS layer."
  // 4. Ensure the LLM has an MCP tool (like `add_wfs_feature` or `geoserver_add_feature`) capable of
  //    parsing this JSON and performing the WFS-T Insert.
}
