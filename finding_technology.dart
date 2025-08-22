import 'package:autheet/functions/bluetooth_pattern_generator.dart';
import 'package:autheet/functions/constant_pattern_generator.dart';
import 'package:autheet/functions/nfc_card_pattern_generator.dart';
import 'package:autheet/functions/pattern_generator.dart';
import 'package:autheet/functions/shaking_pattern_generator.dart';
import 'package:autheet/functions/ntp_service.dart';
import 'package:autheet/functions/uwb_pattern_generator.dart';
import 'package:autheet/providers/nfc_provider.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kReleaseMode, defaultTargetPlatform, TargetPlatform;
import 'package:uwb/flutter_uwb.dart';

/// Enum for the different types of finding technologies.
enum TechnologyType { shakingPattern, constantPattern, uwb, ble, nfcCard }

/// Abstract base class for a technology used to find other users.
/// It defines the common interface for all finding technologies.
abstract class FindingTechnology {
  final String settingsKey;
  final bool defaultEnabled;
  final String nameLocalizationKey;
  final String descriptionLocalizationKey;
  final String technologyName;
  final TechnologyType type;
  final bool isDebug;
  // This is now a factory, not a stored instance
  final PatternGenerator Function() generatorFactory;

  FindingTechnology({
    required this.settingsKey,
    required this.defaultEnabled,
    required this.nameLocalizationKey,
    required this.descriptionLocalizationKey,
    required this.technologyName,
    required this.type,
    required this.generatorFactory,
    this.isDebug = false,
  });

  static List<FindingTechnology>? _availableTechnologies;

  /// Returns a list of all available technologies.
  /// If [force] is true, it rebuilds the list, creating new generator instances.
  static Future<List<FindingTechnology>> getAvailableTechnologies(
    NTPService ntpService,
    NfcProvider nfcProvider, {
    bool force = false,
  }) async {
    if (_availableTechnologies == null || force) {
      _availableTechnologies = [];

      // Shaking pattern is available on mobile platforms
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        _availableTechnologies!.add(ShakingPatternTechnology(ntpService));
        _availableTechnologies!.add(BluetoothPatternTechnology(ntpService));
        final uwbTechnology = UwbTechnology();
        if (await uwbTechnology.isSupported()) {
          _availableTechnologies!.add(uwbTechnology);
        }
        _availableTechnologies!.add(NfcCardTechnology(nfcProvider));
      }

      // Constant pattern is only available in debug mode
      if (kDebugMode) {
        _availableTechnologies!.add(ConstantPatternTechnology());
      }
    }

    if (kReleaseMode) {
      return _availableTechnologies!.where((tech) => !tech.isDebug).toList();
    }
    return _availableTechnologies!;
  }

  static FindingTechnology getNfcCardTechnology(NfcProvider nfcProvider) {
    return NfcCardTechnology(nfcProvider);
  }
}

/// A concrete implementation for the 'shaking pattern' technology.
class ShakingPatternTechnology extends FindingTechnology {
  ShakingPatternTechnology(NTPService ntpService)
    : super(
        settingsKey: 'finding_technology_shaking_pattern_enabled',
        defaultEnabled: true,
        nameLocalizationKey: 'shakingPattern',
        descriptionLocalizationKey: 'shakeYourPhonesToFindEachOther',
        technologyName: 'shakingPattern',
        type: TechnologyType.shakingPattern,
        generatorFactory: () => ShakingPatternGenerator(ntpService),
      );
}

/// A concrete implementation for the Bluetooth LE technology.
class BluetoothPatternTechnology extends FindingTechnology {
  BluetoothPatternTechnology(NTPService ntpService)
    : super(
        settingsKey: 'finding_technology_ble_pattern_enabled',
        defaultEnabled: true,
        nameLocalizationKey: 'bluetooth',
        descriptionLocalizationKey: 'bluetoothDescription',
        technologyName: 'bluetooth',
        type: TechnologyType.ble,
        generatorFactory: () => BluetoothPatternGenerator(),
      );
}

/// A concrete implementation for the test-only 'constant pattern' technology.
class ConstantPatternTechnology extends FindingTechnology {
  ConstantPatternTechnology()
    : super(
        settingsKey: 'finding_technology_constant_pattern_enabled',
        defaultEnabled: false,
        nameLocalizationKey: 'constantPattern',
        descriptionLocalizationKey: 'constantPatternDescription',
        technologyName: 'constantPattern',
        type: TechnologyType.constantPattern,
        generatorFactory: () => ConstantPatternGenerator(),
        isDebug: true,
      );
}

/// A concrete implementation for the UWB technology.
class UwbTechnology extends FindingTechnology {
  UwbTechnology()
    : super(
        settingsKey: 'finding_technology_uwb_enabled',
        defaultEnabled: true,
        nameLocalizationKey: 'uwb',
        descriptionLocalizationKey: 'uwbDescription',
        technologyName: 'uwb',
        type: TechnologyType.uwb,
        generatorFactory: () => UwbPatternGenerator(),
      );

  Future<bool> isSupported() async {
    return await Uwb().isUwbSupported();
  }
}

/// A concrete implementation for the NFC card technology.
class NfcCardTechnology extends FindingTechnology {
  NfcCardTechnology(NfcProvider nfcProvider)
    : super(
        settingsKey: 'finding_technology_nfc_card_enabled',
        defaultEnabled: true,
        nameLocalizationKey: 'nfcCard',
        descriptionLocalizationKey: 'nfcCardDescription',
        technologyName: 'nfcCard',
        type: TechnologyType.nfcCard,
        generatorFactory: () => NfcCardPatternGenerator(nfcProvider),
      );
}
