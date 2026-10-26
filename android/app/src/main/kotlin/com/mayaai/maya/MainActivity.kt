package com.mayaai.maya

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ---- Opening other apps ----
        MethodChannel(messenger, "maya/apps").setMethodCallHandler { call, result ->
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

        // ---- Phone controls ----
        MethodChannel(messenger, "maya/phone").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "torch" -> result.success(setTorch(call.argument<Boolean>("on") ?: true))
                    "volume" -> result.success(changeVolume(call.argument<String>("how") ?: "up"))
                    "ringer" -> result.success(setRinger(call.argument<String>("mode") ?: "ring"))
                    "battery" -> {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        result.success(
                            mapOf(
                                "level" to bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
                                "charging" to bm.isCharging,
                            ),
                        )
                    }
                    "panel" -> result.success(openPanel(call.argument<String>("name") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }

        // ---- Messages from notifications ----
        MethodChannel(messenger, "maya/messages").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasNotificationAccess())
                "openAccess" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "recent" -> result.success(MayaNotificationListener.recent())
                "clear" -> {
                    MayaNotificationListener.clear()
                    result.success(true)
                }
                "reply" -> {
                    val id = (call.argument<Number>("id"))?.toLong() ?: -1L
                    val text = call.argument<String>("text") ?: ""
                    val listener = MayaNotificationListener.instance
                    val msg = MayaNotificationListener.find(id)
                    result.success(listener != null && msg != null && text.isNotBlank() && listener.reply(msg, text))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setTorch(on: Boolean): Boolean {
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = cm.cameraIdList.firstOrNull {
            cm.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return false
        cm.setTorchMode(id, on)
        return true
    }

    private fun changeVolume(how: String): Boolean {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val stream = AudioManager.STREAM_MUSIC
        when (how) {
            "up" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
            "down" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
            "max" -> am.setStreamVolume(stream, am.getStreamMaxVolume(stream), AudioManager.FLAG_SHOW_UI)
            "mute" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, AudioManager.FLAG_SHOW_UI)
            else -> return false
        }
        return true
    }

    private fun setRinger(mode: String): Boolean {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return try {
            am.ringerMode = when (mode) {
                "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                "silent" -> AudioManager.RINGER_MODE_SILENT
                else -> AudioManager.RINGER_MODE_NORMAL
            }
            true
        } catch (e: SecurityException) {
            // Newer Android needs "Do Not Disturb access" for this; open that page instead.
            openPanel("dnd")
            false
        }
    }

    private fun openPanel(name: String): Boolean {
        val action = when (name) {
            "wifi" -> if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS
            "data" -> if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_DATA_ROAMING_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "dnd" -> "android.settings.ZEN_MODE_SETTINGS"
            "brightness" -> Settings.ACTION_DISPLAY_SETTINGS
            else -> return false
        }
        return try {
            startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, MayaNotificationListener::class.java).flattenToString()
        return enabled.split(":").any { it == me || it.startsWith("$packageName/") }
    }
}
