# Kiến trúc

Cập nhật: 27/11/2026, theo nhánh `feat/bp-aha-protocol` (app 1.0.52+53).

```
Flutter app (Android) ──► Supabase  (Auth, Postgres + RLS, Realtime, Storage, Edge Function `push`)
        │                              ▲
        │                              │ service role (chỉ máy chủ)
        └─► Vercel `api/*` ────────────┘
                 ├─► Groq (LLM, STT) · ElevenLabs (TTS) · Gemini (dự phòng)   — qua router xoay vòng key
                 ├─► OpenAI (Vy Live, giọng thời gian thực)                    — khoá nằm mã hoá trong `provider_keys`
                 └─► YouTube Data API (tìm video cho màn Giải trí)

Thông báo đẩy:  trigger/RPC trong Postgres ─► Edge Function `push` ─► FCM ─► máy người nhận
Module ngoài (camera `roi_monitor`) ─► POST /api/alert/trigger ─► push `demo_alert`
```

## Thành phần

| Phần | Thư mục | Việc |
|---|---|---|
| App Flutter | `app/` | Riverpod, go_router, supabase_flutter. Tính năng chia theo `lib/features/*` (auth, home, chat, bp, ocr, health, meds, family, safety, camera, voice, entertainment, plan, push, reminders, update, profile, community) |
| Máy chủ | `api/` | Vercel Functions (Node, vùng `hnd1`, tối đa 30 giây). Mã dùng chung ở `api/_lib/` |
| Cơ sở dữ liệu | `supabase/migrations/` | 0001–0038, mọi bảng bật RLS. Xem `DATABASE.md` |
| Thông báo đẩy | `supabase/functions/push` | Edge Function gửi FCM. Việc quyết định ai nhận và khi nào nằm trong SQL (0019, 0023, 0026, 0037) |
| Web admin | `public/admin` + `api/admin/*` | Đăng nhập admin, thống kê, quản lý khoá API, gói Vy Live. Xem `BAO_MAT_ADMIN.md` |
| Kiểm thử | `app/test` (58 tệp), `api/_tests`, `supabase/tests` | Flutter test, test máy chủ, kiểm RLS bằng SQL |

## Máy chủ (`api/`)

| Đường dẫn | Việc |
|---|---|
| `/api/voice/turn` | Một lượt Vy: nhận câu nói + ngữ cảnh màn hình, trả ý định (intent) và lời đáp. Xử lý bằng luật trước (`_lib/voice/dm.ts`, `dialect.ts`, `nav.ts`, `daily.ts`, `family.ts`, `video_nlu.ts`), chỉ gọi LLM khi luật không hiểu; có rào an toàn khẩn cấp, huyết áp, thuốc (`bp_guard.ts`) |
| `/api/voice/tts`, `/api/tts` | Đọc giọng (ElevenLabs). Hiện app dùng giọng máy (`flutter_tts`) cho mọi câu; ElevenLabs tắt bằng `SpeechPlayer.serverVoice` |
| `/api/stt`, `/api/llm` | Nhận giọng và gọi LLM (Groq), qua router xoay vòng key |
| `/api/ocr` | Đọc ảnh máy đo (Groq vision); `mode=bp` chỉ đọc SYS/DIA/PULSE |
| `/api/health-risk` | Đánh giá nguy cơ đột quỵ + tim mạch 10 năm sau mỗi lần đo hoặc khi sửa hồ sơ |
| `/api/youtube` | Tìm video, lọc nhúng được + an toàn, cache 6 giờ |
| `/api/alert/trigger`, `/api/alert/status` | Cảnh báo khẩn cấp DEMO cho module ngoài. Xem `API_CANH_BAO_DEMO.md` |
| `/api/admin/*` | Đăng nhập, thống kê, cài đặt (khoá API, gói) |
| `/api/cron/prune-chat-images` | Chạy 03:23 mỗi ngày: xoá ảnh chat quá 90 ngày, lịch sử hỏi Vy quá 90 ngày |

- Router: mỗi nhà cung cấp có một key pool; gặp 401/403/429/5xx thì đánh dấu key nghỉ và thử key kế tiếp.
- Khoá API do admin quản lý trong bảng `provider_keys`, lưu mã hoá (`_lib/secretbox.ts`). App không bao giờ giữ `service_role`.

## Vy (trợ lý giọng nói)

- Vy điều khiển toàn bộ app. Mọi màn hình, hành động và ý định được ghi trong `APP_MAP.md` (tài liệu sống: đổi giao diện thì sửa tệp này trong cùng thay đổi).
- Hai chế độ: **Vy thường** (nghe → `/api/voice/turn` → app thực thi) và **Vy Live** (giọng thời gian thực qua WebRTC, theo gói trả phí; thiết kế ở `PREMIUM_LIVE_DESIGN.md`).
- Các nhánh xử lý đáng chú ý: khẩn cấp (nói thẳng + nút Gọi 115 / Báo SOS, không tự gọi), thuốc an toàn (không nói liều), nhắc việc lưu trên máy, mở màn từ bất cứ đâu, giải trí (hiểu chủ đề, nhớ thói quen nghe), người thân hỏi tình hình cha mẹ.
- Chi tiết: `VOICE_AGENT.md`, `VOICE_LATENCY.md`, `KE_HOACH_VY_GIAI_TRI.md`, `KE_HOACH_VY_TONG_THE.md`.

## Vai trò và gia đình

- Mỗi tài khoản là **người cao tuổi** (`elder`) hoặc **người thân** (`family`); vai trò quyết định bộ khung giao diện (migration 0027).
- Liên kết người thân ↔ người cao tuổi đi qua mã mời và quyền theo từng nhóm dữ liệu (0021–0023). Thuốc, SOS, thẻ y tế khẩn cấp, tóm tắt cuối ngày: 0024–0026, 0033.
- Gói Vy Live: người thân mua, người cao tuổi hưởng qua liên kết; admin xác nhận thanh toán (0031–0032).

## Dữ liệu sức khoẻ

- Huyết áp theo chuẩn AHA/ACC: ngồi nghỉ 5 phút, 2 số cách nhau 1 phút (0035, `_lib/health/bp_protocol.ts`). Danh sách tính năng ở `FEATURES.md`.
- Mô hình nguy cơ chạy trên máy chủ (`_lib/health/models.ts`, `risk.ts`); app chỉ ghi hồ sơ và đọc kết quả.

## Phát hành

- Android, tự cập nhật qua bảng `app_versions`; có kênh bản thử `android_preview` cho tài khoản trong `preview_testers`. Xem `RELEASE.md`.
