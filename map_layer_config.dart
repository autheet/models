import 'dart:convert';

enum MapLayerType { wms, xyz }

class MapLayerConfig {
  final String id;
  final String name;
  bool isVisible;
  double opacity;
  final MapLayerType type;

  // Auth options
  final String? username;
  final String? password;
  final String? authToken;

  // WMS options
  final String? wmsBaseUrl;
  final List<String>? wmsLayers;
  final List<String>? wmsStyles;
  final String wmsFormat;
  final bool wmsTransparent;
  final String? wmsVersion;
  final String? wmsCrs;

  // XYZ options
  final String? urlTemplate;
  final List<String> subdomains;

  // Common options
  final Map<String, String>? _headers;
  final String? userAgentPackageName;

  MapLayerConfig({
    required this.id,
    required this.name,
    this.isVisible = true,
    this.opacity = 1.0,
    required this.type,
    this.username,
    this.password,
    this.authToken,
    this.wmsBaseUrl,
    this.wmsLayers,
    this.wmsStyles,
    this.wmsFormat = 'image/png',
    this.wmsTransparent = true,
    this.wmsVersion = '1.1.1',
    this.wmsCrs = 'EPSG:3857',
    this.urlTemplate,
    this.subdomains = const [],
    Map<String, String>? headers,
    this.userAgentPackageName,
  }) : _headers = headers;

  /// Returns headers including authentication if credentials are provided.
  Map<String, String>? get headers {
    final combinedHeaders = <String, String>{...?_headers};

    if (authToken != null) {
      combinedHeaders['Authorization'] = 'Bearer $authToken';
    } else if (username != null && password != null) {
      final bytes = utf8.encode('$username:$password');
      final base64Str = base64.encode(bytes);
      combinedHeaders['Authorization'] = 'Basic $base64Str';
    }

    return combinedHeaders.isNotEmpty ? combinedHeaders : null;
  }

  // Factory for WMS layer
  factory MapLayerConfig.wms({
    required String id,
    required String name,
    required String baseUrl,
    required List<String> layers,
    List<String>? styles,
    String format = 'image/png',
    bool transparent = true,
    String version = '1.1.1',
    String crs = 'EPSG:3857',
    bool isVisible = true,
    double opacity = 1.0,
    String? username,
    String? password,
    String? authToken,
    Map<String, String>? headers,
    String? userAgentPackageName,
  }) {
    return MapLayerConfig(
      id: id,
      name: name,
      type: MapLayerType.wms,
      wmsBaseUrl: baseUrl,
      wmsLayers: layers,
      wmsStyles: styles,
      wmsFormat: format,
      wmsTransparent: transparent,
      wmsVersion: version,
      wmsCrs: crs,
      isVisible: isVisible,
      opacity: opacity,
      username: username,
      password: password,
      authToken: authToken,
      headers: headers,
      userAgentPackageName: userAgentPackageName,
    );
  }

  // Factory for XYZ layer
  factory MapLayerConfig.xyz({
    required String id,
    required String name,
    required String urlTemplate,
    List<String> subdomains = const [],
    bool isVisible = true,
    double opacity = 1.0,
    String? username,
    String? password,
    String? authToken,
    Map<String, String>? headers,
    String? userAgentPackageName,
  }) {
    return MapLayerConfig(
      id: id,
      name: name,
      type: MapLayerType.xyz,
      urlTemplate: urlTemplate,
      subdomains: subdomains,
      isVisible: isVisible,
      opacity: opacity,
      username: username,
      password: password,
      authToken: authToken,
      headers: headers,
      userAgentPackageName: userAgentPackageName,
    );
  }
}
