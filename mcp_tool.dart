import 'package:firebase_ai/firebase_ai.dart';

/// Wrapper class that tracks a tool's origin for dynamic routing
class McpTool {
  final FunctionDeclaration declaration;
  final Map<String, Schema> parameters;
  final String? mcpFunction; // Cloud function name (null for local tools)
  final bool isLocal; // true for screen/location tools

  McpTool({
    required this.declaration,
    required this.parameters,
    this.mcpFunction,
    this.isLocal = false,
  });

  String get name => declaration.name;
}
