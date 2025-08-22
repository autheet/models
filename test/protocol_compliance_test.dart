// test/protocol_compliance_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'dart:convert';

import 'package:autheet/models/protocol_version.dart'; // Import the protocol_version.dart file

void main() {
  // This test uses an LLM to check for differences between the protocol specification and the implementation in the data models.
  test('Protocol Compliance Test', () async {
    // Define the models directory path.
    const modelsPath = 'lib/models';

    // Directly use the constants from protocol_version.dart
    const isDraft = autheetProtocolVersionImplementationStatusDraft;
    const protocolDefinitionFileName = autheetProtocolDefinitionPath;
    const protocolDefinitionUrl = autheetProtocolDefinitionUrl;


    String protocolDefinitionContent;
    try {
      protocolDefinitionContent = await File(
        'lib/models/$protocolDefinitionFileName', // Use the relative path
      ).readAsString();
    } catch (e) {
      // Fallback to downloading from the URL if reading the local file fails.
      // If reading the file fails, try downloading from the URL.
      // print('Failed to read protocol definition file: $e. Trying to download.');
      // final response = await http.get(Uri.parse(protocolDefinitionUrl));
      // protocolDefinitionContent = response.body;
      fail(
        'Could not read protocol definition file from $autheetProtocolDefinitionPath',
      );
    }

    // If not in draft mode, always try to download from the URL to ensure a recent and publicized definition is used.
    if (!isDraft) {
      final response = await http.get(Uri.parse(protocolDefinitionUrl));
      if (response.statusCode != 200) {
        fail(
          'Could not download protocol definition from $protocolDefinitionUrl. Status code: ${response.statusCode}. Before releasing, ensure the protocol definition is publicized and recent.',
        );
      }
      protocolDefinitionContent = response.body;
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
    final fullPrompt = '''
$prompt

<CODE_BLOCK>
$protocolDefinitionContent
</CODE_BLOCK>
''';

    // 8. Execute the Gemini CLI command and pipe the full prompt content to its standard input.
    final process = await Process.start(
      geminiCommand,
      [
      'gen',
      ],
      workingDirectory: modelsPath,
    );
    process.stdin.write(fullPrompt);
    await process.stdin.close();

    // 9. Read the stdout and stderr of the process.
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    final exitCode = await process.exitCode;
    final geminiOutput = await stdoutFuture;
    final geminiError = await stderrFuture;

    if (exitCode != 0) {
      fail('Gemini command "$geminiCommand" failed to execute. Error: $geminiError');
    }
    // 8. Apply conditional logic based on draft status.
    final hasDifferences = !geminiOutput.trim().contains(
      'No differences found.',
    );

    // 9. Handle differences based on draft status.
    if (isDraft) {
      if (hasDifferences) {
        final differencesFile = File('$modelsPath/differences.md');
        await differencesFile.writeAsString(geminiOutput);
        print(
          'Protocol differences found and written to $modelsPath/differences.md',
        );
      } else {
        final differencesFile = File('$modelsPath/differences.md');
        if (await differencesFile.exists()) {
          await differencesFile.delete();
        }
      }
      // In draft mode, the test always passes.
      expect(true, isTrue);
    } else {
      if (hasDifferences) {
        fail(
          'Protocol compliance check failed. Differences found: $geminiOutput',
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
