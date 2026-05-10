package com.example.shopho

import android.content.Intent
import android.os.Bundle
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "shopho/call_native"
        private const val PREFS_NAME = "shopho_call_native"
        private const val KEY_PENDING_CALL_ID = "pending_accept_call_id"
        private const val EXTRA_CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"
        private const val EXTRA_CALL_ID = "EXTRA_CALLKIT_ID"
        private const val ACTION_SUFFIX = ".ACTION_CALL_ACCEPT"
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingAcceptCallId" -> {
                    val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    val callId = prefs.getString(KEY_PENDING_CALL_ID, null)
                    prefs.edit().remove(KEY_PENDING_CALL_ID).apply()
                    result.success(callId)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAcceptIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAcceptIntent(intent)
    }

    private fun handleAcceptIntent(intent: Intent) {
        val action = intent.action ?: return
        if (!action.endsWith(ACTION_SUFFIX)) return

        val data = intent.getBundleExtra(EXTRA_CALL_DATA) ?: return
        val callId = data.getString(EXTRA_CALL_ID) ?: return
        if (callId.isEmpty()) return

        // Persist so CallService.init() can pick it up on cold start.
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit().putString(KEY_PENDING_CALL_ID, callId).apply()

        // Re-fire the accept broadcast so the plugin's EventChannel delivers
        // actionCallAccept to Dart with full call data (extra.order_id etc.).
        // On cold start the Flutter engine isn't ready yet so the event will be
        // dropped, but the SharedPreferences path above covers that case.
        try {
            val broadcastIntent = CallkitIncomingBroadcastReceiver.getIntentAccept(this, data)
            broadcastIntent.addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            sendBroadcast(broadcastIntent)
        } catch (_: Exception) {}

        // Secondary warm-start notification via MethodChannel.
        methodChannel?.invokeMethod("callAccepted", callId)
    }
}
