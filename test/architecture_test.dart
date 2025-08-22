// test/architecture_test.dart
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;

/// Main function to run architectural tests.
void main() {
  group('Architecture Tests', () {
    test(
      'autheetProtocolVersion is defined only in protocol_version.dart',
      () async {
        final libDirectory = Directory('lib');
        final dartFiles = libDirectory
            .listSync(recursive: true)
            .where((entity) => entity.path.endsWith('.dart'));

        final filesWithProtocolVersion = <String>[];

        for (final file in dartFiles) {
          final content = await File(file.path).readAsString();
          if (content.contains('autheetProtocolVersion') &&
              !file.path.endsWith(
                path.join('lib', 'models', 'protocol_version.dart'),
              )) {
            filesWithProtocolVersion.add(file.path);
          }
        }

        expect(
          filesWithProtocolVersion,
          isEmpty,
          reason:
              'The variable autheetProtocolVersion should only be defined in lib/models/protocol_version.dart',
        );
      },
    );
  });
}

// test/architecture_test.dart
