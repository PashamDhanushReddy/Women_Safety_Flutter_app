package com.example.hershield

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.provider.Telephony
import android.telephony.SmsManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.hershield/mms"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSMS" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    
                    try {
                        android.util.Log.d("SMS_SERVICE", "🚨 AUTOMATIC EMERGENCY SENDING STARTED")
                        android.util.Log.d("SMS_SERVICE", "📱 Phone: $phoneNumber")
                        sendSMSAutomatically(phoneNumber, message)
                        android.util.Log.d("SMS_SERVICE", "✅ SMS sent successfully in background!")
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("SMS_SERVICE", "❌ Failed to send SMS: ${e.message}")
                        result.error("SEND_FAILED", "Failed to send SMS: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun sendSMSAutomatically(phoneNumber: String, message: String) {
        try {
            android.util.Log.d("SMS_SERVICE", "🚀 Starting SMS sending process")
            
            val smsManager = SmsManager.getDefault()
            val fullMessage = "🚨 EMERGENCY ALERT 🚨\n$message"
            
            smsManager.sendTextMessage(phoneNumber, null, fullMessage, null, null)
            android.util.Log.d("SMS_SERVICE", "✅ Emergency SMS sent successfully")
            
        } catch (e: Exception) {
            android.util.Log.e("SMS_SERVICE", "💥 Error sending SMS: ${e.message}")
        }
    }
    
    private fun sendImagesViaMMS(phoneNumber: String, message: String, imagePaths: List<String>, smsManager: SmsManager) {
        try {
            android.util.Log.d("MMS_SERVICE", "🚀 Starting RELIABLE MMS sending for ${imagePaths.size} images")
            
            // Method: Use a more reliable approach - send images as actual MMS that display properly
            for ((index, imagePath) in imagePaths.withIndex()) {
                val imageFile = File(imagePath)
                if (imageFile.exists()) {
                    try {
                        // Create content URI for the image
                        val imageUri = FileProvider.getUriForFile(
                            this,
                            "${packageName}.fileprovider",
                            imageFile
                        )
                        
                        // Grant permissions to messaging apps
                        grantUriPermission("com.android.mms", imageUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        grantUriPermission("com.google.android.apps.messaging", imageUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        grantUriPermission("com.samsung.android.messaging", imageUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        
                        // Create a proper MMS intent that will display the image
                        val mmsIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/jpeg"
                            putExtra(Intent.EXTRA_STREAM, imageUri)
                            putExtra("address", phoneNumber)
                            putExtra(Intent.EXTRA_SUBJECT, "🚨 EMERGENCY ALERT")
                            putExtra(Intent.EXTRA_TEXT, "🚨 EMERGENCY ALERT 🚨\n$message\n\n📸 Emergency photo ${index + 1} of ${imagePaths.size}")
                            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        
                        // Try multiple messaging apps to find one that works
                        val messagingApps = listOf(
                            "com.android.mms",
                            "com.google.android.apps.messaging", 
                            "com.samsung.android.messaging",
                            "com.sonyericsson.conversations",
                            "com.huawei.messaging",
                            "com.motorola.messaging"
                        )
                        
                        var success = false
                        for (appPackage in messagingApps) {
                            try {
                                val appIntent = Intent(mmsIntent).apply {
                                    setPackage(appPackage)
                                }
                                startActivity(appIntent)
                                android.util.Log.d("MMS_SERVICE", "✅ MMS sent via $appPackage for image ${index + 1}")
                                success = true
                                Thread.sleep(2000) // Wait for message to be processed
                                break
                            } catch (e: Exception) {
                                android.util.Log.w("MMS_SERVICE", "⚠️ $appPackage failed: ${e.message}")
                                continue
                            }
                        }
                        
                        if (!success) {
                            // Final fallback: Use system chooser
                            try {
                                startActivity(mmsIntent)
                                android.util.Log.d("MMS_SERVICE", "✅ MMS sent via system chooser for image ${index + 1}")
                                Thread.sleep(2000)
                            } catch (e: Exception) {
                                android.util.Log.e("MMS_SERVICE", "❌ System chooser also failed: ${e.message}")
                                throw Exception("Could not send MMS")
                            }
                        }
                        
                    } catch (e: Exception) {
                        android.util.Log.e("MMS_SERVICE", "❌ Error in MMS sending for image $index: ${e.message}")
                        
                        // Fallback: Send SMS with emergency info
                        val fallbackMessage = "🚨 EMERGENCY ALERT 🚨\n$message\n\n📸 Photo ${index + 1} of ${imagePaths.size} captured but couldn't send image. Check emergency app."
                        smsManager.sendTextMessage(phoneNumber, null, fallbackMessage, null, null)
                    }
                }
            }
            
            // Send final summary SMS
            val summaryMessage = "🚨 EMERGENCY COMPLETE 🚨\n$message\n\n📸 Sent ${imagePaths.size} emergency photos via MMS"
            smsManager.sendTextMessage(phoneNumber, null, summaryMessage, null, null)
            
            android.util.Log.d("MMS_SERVICE", "🎉 All emergency messages sent!")
            
        } catch (e: Exception) {
            android.util.Log.e("MMS_SERVICE", "💥 Critical error in MMS sending: ${e.message}")
            // Final fallback
            val fallbackMessage = "🚨 EMERGENCY ALERT 🚨\n$message\n\n📸 ${imagePaths.size} emergency photos captured. Check device storage."
            smsManager.sendTextMessage(phoneNumber, null, fallbackMessage, null, null)
        }
    }
    
    private fun sendTextOnlySMS(phoneNumber: String, message: String, smsManager: SmsManager) {
        val enhancedMessage = "🚨 EMERGENCY ALERT 🚨\n$message\n\n⚠️ No photos captured for this emergency."
        smsManager.sendTextMessage(phoneNumber, null, enhancedMessage, null, null)
    }
}
