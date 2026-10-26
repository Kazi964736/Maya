"""Run after `flutter create --platforms android .` to finish the Android setup.

flutter_local_notifications needs Java 8+ API "desugaring" switched on in the
app's Gradle file. This script adds it to build.gradle.kts or build.gradle,
whichever `flutter create` generated, and is safe to run more than once.
"""
import pathlib
import re
import sys

DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"
app = pathlib.Path(__file__).resolve().parent.parent / "android" / "app"
kts = app / "build.gradle.kts"
groovy = app / "build.gradle"

if kts.exists():
    path, flag, dep = kts, "isCoreLibraryDesugaringEnabled = true", f'coreLibraryDesugaring("{DESUGAR}")'
elif groovy.exists():
    path, flag, dep = groovy, "coreLibraryDesugaringEnabled true", f"coreLibraryDesugaring '{DESUGAR}'"
else:
    sys.exit("No android/app/build.gradle(.kts) found. Run `flutter create --platforms android .` first.")

text = path.read_text()

if "CoreLibraryDesugaringEnabled" not in text and "coreLibraryDesugaringEnabled" not in text:
    text, n = re.subn(r"compileOptions\s*\{", "compileOptions {\n        " + flag, text, count=1)
    if n == 0:
        text = re.sub(
            r"android\s*\{",
            "android {\n    compileOptions {\n        " + flag + "\n    }",
            text,
            count=1,
        )

if "desugar_jdk_libs" not in text:
    text += "\ndependencies {\n    " + dep + "\n}\n"

# Release builds shrink the code (R8). Keep the classes flutter_local_notifications
# reads back through Gson, otherwise the app can crash on start-up or when scheduling.
RULES = """# flutter_local_notifications + Gson (needed for release builds)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
"""
(app / "proguard-rules.pro").write_text(RULES)

if "proguard-rules.pro" not in text:
    if path is kts:
        line = 'proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'
    else:
        line = "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'"
    m = re.search(r"buildTypes\s*\{", text)
    rel = re.compile(r"release\s*\{")
    r = rel.search(text, m.end()) if m else None
    if r:
        text = text[: r.end()] + "\n            " + line + text[r.end():]
    else:
        text = re.sub(
            r"android\s*\{",
            "android {\n    buildTypes {\n        release {\n            " + line + "\n        }\n    }",
            text,
            count=1,
        )

path.write_text(text)
print(f"Desugaring and keep-rules set up in {path.relative_to(app.parent.parent)}")
