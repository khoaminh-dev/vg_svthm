package com.viegrand.vg_svthm

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Số đang chờ người dùng cho phép quyền gọi lần đầu.
    private var pendingCall: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Kênh thông báo mức cao để tin nhắn hiện nổi lên màn hình và có âm báo.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("viegrand_default", "Tin nhắn và cập nhật", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Thông báo tin nhắn mới và bản cập nhật Viegrand"
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    // Gọi thẳng (Vy): chỉ app Dart gọi kênh này, và CHỈ với số của người liên hệ trong thẻ y tế hoặc 115, sau đếm ngược có nút Huỷ.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vg.call").setMethodCallHandler { call, result ->
            when (call.method) {
                "call" -> {
                    // Chỉ giữ chữ số và dấu + (chặn ký tự điều khiển như * và #).
                    val number = (call.argument<String>("number") ?: "").filter { it.isDigit() || it == '+' }
                    if (number.length < 3 || number.length > 16) {
                        result.error("bad_number", "Số điện thoại không hợp lệ", null)
                    } else if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) {
                        result.success("no_telephony")
                    } else if (checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                        startCall(number, Intent.ACTION_CALL)
                        result.success("calling")
                    } else {
                        pendingCall = number
                        requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), CALL_REQUEST)
                        result.success("asking")
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startCall(number: String, action: String) {
        val i = Intent(action, Uri.parse("tel:" + Uri.encode(number)))
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(i)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALL_REQUEST) return
        val n = pendingCall ?: return
        pendingCall = null
        // Cho phép thì gọi luôn; từ chối thì mở bàn phím gọi có số điền sẵn.
        val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        startCall(n, if (ok) Intent.ACTION_CALL else Intent.ACTION_DIAL)
    }

    companion object {
        private const val CALL_REQUEST = 7
    }
}
