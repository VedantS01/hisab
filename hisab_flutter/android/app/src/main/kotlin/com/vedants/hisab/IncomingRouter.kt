package com.vedants.hisab

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Statement files opened or shared into Hisab, and hisab:// links, handed to
 * Dart (lib/services/incoming_router.dart). Twin of ios/Runner/IncomingRouter.swift:
 * queued until Dart asks once, pushed as they arrive after that.
 */
class IncomingRouter(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "hisab/incoming")
    private val pending = mutableListOf<Map<String, String>>()
    private var dartListening = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "pending") return@setMethodCallHandler result.notImplemented()
            dartListening = true
            result.success(pending.toList())
            pending.clear()
        }
    }

    fun receive(intent: Intent?) {
        val item = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uri ->
                if (uri.scheme == "hisab") mapOf("kind" to "link", "url" to uri.toString())
                else stage(uri)
            }
            Intent.ACTION_SEND -> stream(intent)?.let(::stage)
            else -> null
        } ?: return
        if (dartListening) channel.invokeMethod("open", item) else pending.add(item)
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    /** A private copy Dart can read and delete; a content:// URI is only
     *  readable through the resolver, and only while the grant lasts. */
    private fun stage(uri: Uri): Map<String, String>? {
        return try {
            val name = displayName(uri) ?: "statement"
            val dir = File(context.cacheDir, "incoming").apply { mkdirs() }
            val target = File(dir, "${UUID.randomUUID()}-$name")
            context.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { input.copyTo(it) }
            } ?: return null
            mapOf("kind" to "file", "path" to target.path, "name" to name)
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
            ?: uri.lastPathSegment
}
