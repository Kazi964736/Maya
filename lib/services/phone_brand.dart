import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../settings.dart';

/// Brands whose battery savers often stop background alarms and reminders
/// unless the app is allowed to run in the background / auto-start.
const _aggressiveBrands = [
  'xiaomi', 'redmi', 'poco', 'vivo', 'iqoo', 'oppo', 'realme', 'oneplus', 'infinix', 'tecno', 'itel', 'huawei', 'honor',
];

String? _brandCache;

Future<String> phoneBrand() async {
  if (_brandCache != null) {
    return _brandCache!;
  }
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    _brandCache = '${info.manufacturer} ${info.brand}'.toLowerCase();
  } catch (e) {
    debugPrint('Device info failed: $e');
    _brandCache = '';
  }
  return _brandCache!;
}

Future<bool> isAggressiveBatteryBrand() async {
  final brand = await phoneBrand();
  return _aggressiveBrands.any(brand.contains);
}

/// Opens Maya's own "App info" page (Battery / Autostart / Notifications live here).
Future<void> openMayaAppInfo() async {
  try {
    await AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$appPackage',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    ).launch();
  } catch (e) {
    debugPrint('Open app settings failed: $e');
  }
}

/// Opens the phone's battery-optimisation list.
Future<void> openBatterySettings() async {
  try {
    await AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    ).launch();
  } catch (_) {
    await openMayaAppInfo();
  }
}

/// Opens text-to-speech settings so a Bengali / Hindi voice can be installed.
Future<void> openVoiceSettings() async {
  try {
    await AndroidIntent(action: 'com.android.settings.TTS_SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
  } catch (_) {
    await AndroidIntent(action: 'android.settings.SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
  }
}

/// Opens the Google app's page so its offline speech languages can be added.
Future<void> openSpeechSettings() async {
  try {
    await AndroidIntent(
      action: 'android.settings.VOICE_INPUT_SETTINGS',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    ).launch();
  } catch (_) {
    await AndroidIntent(action: 'android.settings.SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
  }
}
