package com.example.calculator

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Reads the SMS inbox for Smart Import. Only `date` and `body` are queried. */
object SmsInboxChannel {
    private const val NAME = "masarifi/sms"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            if (call.method != "readInbox") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val after = (call.argument<Number>("after") ?: 0).toLong()
            result.success(readInbox(context, after))
        }
    }

    private fun readInbox(context: Context, after: Long): List<Map<String, Any>> {
        val granted = context.checkSelfPermission(Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) return emptyList()

        val rows = mutableListOf<Map<String, Any>>()
        val cursor = context.contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("date", "body"),
            "date > ?",
            arrayOf(after.toString()),
            "date ASC",
        ) ?: return rows
        cursor.use {
            while (it.moveToNext()) {
                rows.add(mapOf("date" to it.getLong(0), "body" to (it.getString(1) ?: "")))
            }
        }
        return rows
    }
}
