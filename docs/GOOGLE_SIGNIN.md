# Cấu hình đăng nhập Google

App dùng `google_sign_in` (chọn tài khoản ngay trong app) rồi đưa ID token cho Supabase. Miễn phí.

Package Android: `com.viegrand.vg_svthm`.

## 1. Google Cloud Console

1. Vào <https://console.cloud.google.com>, tạo project (hoặc dùng project có sẵn).
2. **APIs & Services > OAuth consent screen**: chọn External, điền tên app và email, thêm email của bạn vào Test users (khi còn ở chế độ Testing).
3. **APIs & Services > Credentials > Create credentials > OAuth client ID**, tạo lần lượt:
   - **Web application**: lấy **Client ID** và **Client secret** (dùng cho Supabase và biến `GOOGLE_WEB_CLIENT_ID`).
     Authorized redirect URI: `https://jsntzeyrnhwiflydcmfd.supabase.co/auth/v1/callback`
   - **Android**: Package name `com.viegrand.vg_svthm`, SHA-1 của máy bạn (lệnh bên dưới).
   - **iOS** (nếu làm iOS): Bundle ID `com.viegrand.vgSvthm`, lấy **Client ID** (biến `GOOGLE_IOS_CLIENT_ID`).

Lấy SHA-1 debug trên Windows:

```
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Bản release dùng keystore khác, cần tạo thêm một Android client với SHA-1 của keystore đó.

## 2. Supabase

**Authentication > Providers > Google**: bật, dán Web Client ID và Client secret, lưu.
Với iOS, bật thêm "Skip nonce checks".

## 3. App

Điền vào `app/env.json` (file này nằm trong `.gitignore`):

```json
"GOOGLE_WEB_CLIENT_ID": "xxx.apps.googleusercontent.com",
"GOOGLE_IOS_CLIENT_ID": ""
```

Chạy: `flutter run --dart-define-from-file=env.json`

Chỉ cần Web Client ID cho Android. Client ID Android chỉ để Google nhận ra app (khớp package và SHA-1), không điền vào code.

## 4. iOS (nếu làm)

Thêm vào `ios/Runner/Info.plist` một URL scheme là REVERSED_CLIENT_ID (dạng `com.googleusercontent.apps.xxxx`, lấy từ iOS Client ID đảo ngược).

## Luồng

Đăng nhập Google lần đầu: trigger `handle_new_user` tạo profile với username rỗng, tên và ảnh lấy từ Google. App chuyển sang màn "Hoàn tất hồ sơ" để chọn username rồi mới vào trang chủ.
