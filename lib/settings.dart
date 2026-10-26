import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android application id (must match `flutter create --org com.mayaai --project-name maya`).
const appPackage = 'com.mayaai.maya';

/// A language the assistant can listen and speak in.
class AppLanguage {
  const AppLanguage(this.code, this.label, this.speechLocale, this.ttsLocale);

  /// Short code used in prompts and replies: 'bn', 'hi', 'en'.
  final String code;
  final String label;

  /// Locale for speech recognition (speech_to_text uses underscores).
  final String speechLocale;

  /// Locale for text-to-speech.
  final String ttsLocale;
}

const languages = <AppLanguage>[
  AppLanguage('bn', 'বাংলা', 'bn_IN', 'bn-IN'),
  AppLanguage('hi', 'हिंदी', 'hi_IN', 'hi-IN'),
  AppLanguage('en', 'English', 'en_IN', 'en-IN'),
];

AppLanguage languageByCode(String? code) =>
    languages.firstWhere((l) => l.code == code, orElse: () => languages.first);

/// User settings, saved on the phone.
class Settings extends ChangeNotifier {
  Settings._();
  static final instance = Settings._();

  late SharedPreferences _prefs;

  AppLanguage language = languages.first;
  String apiKey = '';
  String model = 'auto';
  String city = 'Berhampore';
  String userName = '';
  bool listenOnOpen = true;
  bool conversationMode = false;
  bool speakReplies = true;

  bool get hasAi => apiKey.trim().isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    language = languageByCode(_prefs.getString('language'));
    apiKey = _prefs.getString('apiKey') ?? '';
    model = _prefs.getString('model') ?? model;
    // Older versions saved a fixed model name; let Maya choose the best free one now.
    if (const {'gemini-2.5-flash', 'gemini-3.8-flash'}.contains(model)) {
      model = 'auto';
      await _prefs.setString('model', model);
    }
    city = _prefs.getString('city') ?? city;
    userName = _prefs.getString('userName') ?? '';
    listenOnOpen = _prefs.getBool('listenOnOpen') ?? true;
    conversationMode = _prefs.getBool('conversationMode') ?? false;
    speakReplies = _prefs.getBool('speakReplies') ?? true;
  }

  Future<void> update({
    AppLanguage? language,
    String? apiKey,
    String? model,
    String? city,
    String? userName,
    bool? listenOnOpen,
    bool? conversationMode,
    bool? speakReplies,
  }) async {
    if (language != null) {
      this.language = language;
      await _prefs.setString('language', language.code);
    }
    if (apiKey != null) {
      this.apiKey = apiKey.trim();
      await _prefs.setString('apiKey', this.apiKey);
    }
    if (model != null && model.trim().isNotEmpty) {
      this.model = model.trim();
      await _prefs.setString('model', this.model);
    }
    if (city != null && city.trim().isNotEmpty) {
      this.city = city.trim();
      await _prefs.setString('city', this.city);
    }
    if (userName != null) {
      this.userName = userName.trim();
      await _prefs.setString('userName', this.userName);
    }
    if (listenOnOpen != null) {
      this.listenOnOpen = listenOnOpen;
      await _prefs.setBool('listenOnOpen', listenOnOpen);
    }
    if (conversationMode != null) {
      this.conversationMode = conversationMode;
      await _prefs.setBool('conversationMode', conversationMode);
    }
    if (speakReplies != null) {
      this.speakReplies = speakReplies;
      await _prefs.setBool('speakReplies', speakReplies);
    }
    notifyListeners();
  }

  SharedPreferences get prefs => _prefs;
}
