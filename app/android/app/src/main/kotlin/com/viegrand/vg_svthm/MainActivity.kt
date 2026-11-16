package com.viegrand.vg_svthm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Kênh thông báo mức cao để tin nhắn hiện nổi lên màn hình và có âm báo.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("viegrand_default", "Tin nhắn và cập nhật", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Thông báo tin nhắn mới và bản cập nhật Viegrand"
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
}
