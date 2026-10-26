# Bolo 🎙️ (বলো / बोलो)

A voice assistant for Android that understands **Bengali, Hindi and English**.

## What it does

Works without any key:
- **Call** a contact — "মা কে ফোন করো", "माँ को फोन करो", "Call Rahul"
- **Alarms and timers** — "সকাল ৬টায় অ্যালার্ম দাও", "10 मिनट का टाइमर"
- **Reminders** with notifications — "Remind me to pay the bill at 6 pm"
- **Open apps** — "YouTube খোলো", "open PhonePe"
- **WhatsApp** — "WhatsApp Rahul: I'll be late" (opens WhatsApp with the message; you tap Send)
- **Directions** — "navigate to Berhampore station"
- **Weather** and a **good-morning briefing** (weather + today's reminders)
- Chat history, typing as well as speaking, light/dark theme

With a free Gemini key (Settings):
- **Answers to any question**, in your language, remembering the conversation
- Understands free-form commands ("tell Rahul I'll be 10 minutes late on WhatsApp")
- **Explain a photo** — bills, letters, notices, medicine strips
- **Conversation mode** — keeps listening after each answer, hands-free

It can also be set as the phone's assistant (Settings → Default apps → Digital assistant app), on phones that
allow third-party assistants, so a long-press of home/power opens it listening.

## Build

Codemagic builds it automatically from `codemagic.yaml` (start "Bolo – test APK"). Locally, with Flutter 3.27+:

```
flutter create --org com.boloai --platforms android --project-name bolo .
rm -f test/widget_test.dart
python3 tool/prepare_android.py
flutter pub get
flutter test
flutter build apk
```

## Before publishing

- Move the Gemini call to a small server so the key isn't inside the app.
- Release signing key, Play Console declarations for contacts, calls, microphone and exact alarms, and a privacy policy.
