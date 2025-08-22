// test/protocol_compliance_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'package:autheet/models/protocol_version.dart'; // Import the protocol_version.dart file

void main() {
  // Define the path for the output file in the working directory.
  const String outputFilePath = 'protocol_compliance_test_result.md';

  // This test uses an LLM to check for differences between the protocol specification and the implementation in the data models.
  test('Protocol Compliance Test', () async {
    // Define the models directory path.
    const modelsPath = 'lib/models';

    // Directly use the constants from protocol_version.dart
    const isDraft = autheetProtocolVersionImplementationStatusDraft;
    const protocolDefinitionFileName = autheetProtocolDefinitionPath;
    const protocolDefinitionUrl = autheetProtocolDefinitionUrl;

    String? protocolDefinitionContent;
    final localProtocolDefinitionFile = File('$protocolDefinitionFileName');
    if (await localProtocolDefinitionFile.exists()) {
      try {
        protocolDefinitionContent = await localProtocolDefinitionFile
            .readAsString();
      } catch (e) {
        print(
          'Warning: Could not read protocol definition file from lib/models/$autheetProtocolDefinitionPath: $e',
        );
      }
    }
    // If local file reading failed OR if not in draft mode, attempt to download from the URL.
    if (protocolDefinitionContent == null || !isDraft) {
      print(
        'Attempting to download protocol definition from $protocolDefinitionUrl',
      );
      final response = await http.get(Uri.parse(protocolDefinitionUrl));

      if (response.statusCode != 200) {
        fail(
          'Could not download protocol definition from $protocolDefinitionUrl. Status code: ${response.statusCode}. '
          'For non-draft releases, the protocol definition must be publicized and accessible.',
        );
      }
      protocolDefinitionContent = response.body;
    } else {
      // If in draft mode and local file was successfully read, print a message.
      print(
        'Using local protocol definition file: lib/models/$autheetProtocolDefinitionPath',
      );
    }
    if (protocolDefinitionContent == null ||
        protocolDefinitionContent.isEmpty) {
      fail(
        'Protocol definition content is empty after attempting to read or download. '
        'Ensure the local file exists and is not empty, or the URL provides valid content.',
      );
    }

    // 5. Construct the concise prompt that instructs the LLM on its task.
    final prompt = """
      You are a protocol compliance checker. Your context includes a markdown protocol definition and several Dart data model files.
      Summarize the key differences between the markdown specification and the implementation in the Dart files.
      Focus on data structures, fields, and types.
      If there are no significant differences, respond ONLY with the text 'No differences found.'.
      If there are differences, provide a concise summary.
    """;

    // 6. Determine the correct Gemini command based on the environment.
    final isNixEnvironment = Platform.environment.containsKey('IN_NIX_SHELL');
    final geminiCommand = isNixEnvironment ? 'gemini-cli' : 'gemini';

    // 7. Construct the full prompt content including the protocol definition.
    final fullPrompt =
        '''
$prompt

<CODE_BLOCK>
$protocolDefinitionContent
</CODE_BLOCK>
''';

    // 8. Execute the Gemini CLI command and pipe the full prompt content to its standard input.
    final process = await Process.start(geminiCommand, ['gen']);
    process.stdin.write(fullPrompt);
    await process.stdin.close();

    // 9. Read the stdout and stderr of the process.
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    final exitCode = await process.exitCode;
    final geminiOutput = await stdoutFuture;
    final geminiError = await stderrFuture;

    if (exitCode != 0) {
      fail(
        'Gemini command "$geminiCommand" failed to execute. Error: $geminiError',
      );
    }
    // 8. Apply conditional logic based on draft status.
    final hasDifferences = !geminiOutput.trim().contains(
      'No differences found.',
    );

    // Write the Gemini output to the specified file in the working directory.
    final outputFile = File(outputFilePath);
    await outputFile.writeAsString(geminiOutput);
    print('Gemini output written to ${outputFile.path}');

    // 9. Handle differences based on draft status.
    if (isDraft) {
      // In draft mode, the test always passes.
      expect(true, isTrue);
    } else {
      if (hasDifferences) {
        // In non-draft mode, fail the test if differences are found.
        fail(
          'Protocol compliance check failed. Differences found. Details in ${outputFile.path}',
        );
      } else {
        // In release mode, the test passes only if there are no differences.
        expect(
          hasDifferences,
          isFalse,
          reason: 'No differences should be found in release mode.',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
