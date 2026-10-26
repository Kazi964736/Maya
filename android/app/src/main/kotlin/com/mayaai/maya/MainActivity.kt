package com.mayaai.maya

import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Opens other apps the reliable way (the app's own launch intent) and lists
 * the apps on the phone, so "open <any app>" works for whatever is installed.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maya/apps").setMethodCallHandler { call, result ->
            when (call.method) {
                "launch" -> {
                    val pkg = call.argument<String>("package")
                    val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                    if (intent == null) {
                        result.success(false)
                    } else {
                        try {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "installed" -> {
                    try {
                        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val apps = packageManager.queryIntentActivities(main, PackageManager.MATCH_ALL)
                            .map { mapOf("label" to it.loadLabel(packageManager).toString(), "package" to it.activityInfo.packageName) }
                            .distinctBy { it["package"] }
                        result.success(apps)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
