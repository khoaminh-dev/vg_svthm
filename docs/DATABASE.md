# Database (Supabase / Postgres)

Project: **Viegrand** (`jsntzeyrnhwiflydcmfd`, region ap-northeast-1).
Cập nhật: 27/11/2026 (migration 0001–0038; trên Supabase thật đã có đến 0038, **trừ 0036**). Bảng `supabase_migrations` của Supabase chỉ ghi các bản chạy qua công cụ migration; nhiều bản chạy bằng SQL editor nên không hiện ở đó, hãy kiểm tra bằng cách xem bảng/cột có tồn tại.

## Sơ đồ bảng (schema `public`)

| Bảng | Nội dung | Ghi chú |
|---|---|---|
| `profiles` | 1-1 với `auth.users`: `username` (duy nhất, null với tài khoản Google chưa hoàn tất hồ sơ), `display_name`, `avatar_url`, `last_seen_at` | Trigger `on_auth_user_created` tự tạo |
| `rooms` | `name`, `type` (`group` / `direct`), `direct_key` (duy nhất, chỉ phòng 1-1), `created_by` | Tên 1-50 ký tự |
| `room_members` | (`room_id`, `user_id`) | Bật realtime |
| `messages` | `room_id`, `user_id`, `content` (1-2000 ký tự), `created_at` | Bật realtime, index (`room_id`, `created_at`) |
| `ocr_records` | `title`, `raw_text`, `values` (jsonb: danh sách `{label, value, unit}`), `image_path` | Index (`user_id`, `created_at`) |

Storage:
- `avatars`: công khai để đọc, mỗi người chỉ ghi vào thư mục mang user id của mình.
- `ocr-images`: riêng tư, mỗi người chỉ đọc/ghi/xoá thư mục của mình (xem ảnh qua signed URL).

## Hàm (RPC)

| Hàm | Quyền | Việc |
|---|---|---|
| `is_username_available(text)` | anon, authenticated | Kiểm tra username còn trống (form đăng ký) |
| `create_or_get_direct_room(text)` | authenticated | Mở/tạo chat 1-1 với một `@username` |
| `add_member_by_username(uuid, text)` | authenticated | Thành viên phòng nhóm mời người khác |
| `my_rooms()` | authenticated | Phòng của tôi + thông tin người kia (chat 1-1); chạy dưới quyền người gọi |
| `is_room_member(uuid)` | authenticated | Dùng trong chính sách RLS |
| `handle_new_user()` | không ai | Trigger tạo profile |

## Quy tắc

1. **Mọi thay đổi là một file mới** trong `supabase/migrations/` (đánh số `0005_...`). Không sửa file đã chạy.
2. File `0001` được sửa vài lần lúc đầu vì khi đó chưa chạy ở đâu; từ `0001` đã áp dụng lên Supabase thì cố định.
3. **Mọi bảng bật RLS.** Hàm `security definer` luôn thu hồi quyền của `public`/`anon` trừ khi chủ ý công khai.
4. Sau mỗi lần sửa schema, chạy kiểm tra bảo mật của Supabase (Advisors). Cảnh báo còn lại hiện là chủ ý: `is_username_available` công khai; `rls_auto_enable` do Supabase tạo.
5. Không dùng `service_role` key trong app. App chỉ có URL và key publishable.

## Lịch sử migration

| File | Nội dung |
|---|---|
| `0001_init.sql` | Bảng, trigger profile, bucket avatars, RLS, realtime cho `messages` |
| `0002_harden_functions.sql` | Thu hồi quyền gọi hàm không cần thiết |
| `0003_chat.sql` | Chỉ tự thêm vào phòng do mình tạo; hàm mời thành viên; giới hạn độ dài |
| `0004_direct_chat.sql` | Chat 1-1, `my_rooms()`, realtime cho `room_members` |
| `0005_ocr.sql` | Bucket `ocr-images`, cột `ocr_records.title`, index lịch sử |
| `0006_events.sql` | Bảng `events`: nhật ký thao tác cho web admin |
| `0007_bp_readings.sql` | Bảng `bp_readings`, hàm `bp_category()` (AHA 2017) |
| `0008_hardening.sql` | Client chỉ tạo phòng nhóm; phòng 1-1 chỉ qua RPC |
| `0009_username_self.sql` | `is_username_available` coi username của chính người đang đăng nhập là còn trống (hoàn tất hồ sơ thử lại an toàn) |
| `0010_scale.sql` | Index, thống kê admin tính trong SQL, giới hạn tần suất dùng chung (`api_rate`) cho ~500 người dùng |
| `0011_events_rate_limit_definer.sql` | Sửa lỗi "permission denied" khi ghi `events` (trigger đếm chạy dưới quyền chủ hàm) |
| `0012_voice.sql` | Vy: `provider_keys`, `voice_policy`, `voice_turns`, `voice_tts_log`, `voice_aliases`, `voice_prefs`, `voice_tiers` |
| `0013_chat_images.sql` | Gửi ảnh trong chat, ảnh hết hạn sau 90 ngày |
| `0013_health.sql` | `health_profile`, `health_assessments` (đánh giá nguy cơ tự động) |
| `0014_app_versions.sql` | Bảng `app_versions` cho tự cập nhật |
| `0014_health_qa.sql` | `health_qa`: lịch sử hỏi Vy về sức khoẻ (xoá sau 90 ngày) |
| `0015_community.sql` | `app_flags`, RPC `community_users` (cộng đồng thử nghiệm) |
| `0016_health_trial.sql` | Đồng ý nghiên cứu, `health_feedback` (đợt thử nguy cơ) |
| `0017_rooms_last_message.sql` | Tin cuối + số tin chưa đọc ở `my_rooms()` |
| `0018_speak_advice.sql` | Công tắc "Đọc lời khuyên sau khi đo" trong `voice_prefs` |
| `0019_push.sql` | `device_tokens`, `push_prefs`, trigger gọi Edge Function `push` |
| `0020_health_profile_diabetes.sql` | Thêm tiểu đường vào hồ sơ sức khoẻ |
| `0021_family_links.sql` | `family_links`, `link_codes`, `link_attempts`, `family_audit`: liên kết người thân |
| `0022_family_rls.sql` | Người chăm sóc đã liên kết đọc được dữ liệu sức khoẻ theo quyền từng người (không mở tin nhắn, `voice_*`, OCR) |
| `0023_family_push.sql` | Thông báo gia đình: huyết áp rất cao, có người liên kết/rời, "nhờ đo huyết áp" |
| `0024_meds.sql` | Thuốc: `med_plans`, `med_slots`, `med_items`, `med_prn`, `dose_events`; múi giờ trong `profiles` |
| `0025_meds_replace_fix.sql` | Đơn bị thay/kết thúc thì xoá mọi lần chưa uống của nó |
| `0026_safety_net.sql` | SOS (`sos_events`), thẻ y tế (`emergency_cards`), tóm tắt cuối ngày, nhắc sắp hết/tái khám, giờ yên tĩnh, `notice_log` |
| `0027_roles.sql` | Vai trò `elder` / `family` trong `profiles` |
| `0028_camera.sql` | Cờ `camera` (mặc định tắt) |
| `0029_openai_admin.sql` | Quản lý khoá OpenAI (mã hoá, chống trùng), nền cho Vy Live (`live_users`) |
| `0030_profile_phones.sql` | `profile_phones`: số điện thoại để Vy gọi (bảng riêng) |
| `0031_subscriptions.sql` | `plans`, `subscriptions`, `plan_settings`: gói Vy Live |
| `0032_plan_request_wording.sql` | Thanh toán tượng trưng: người dùng gửi yêu cầu, admin Duyệt; đổi lời nhắn mặc định |
| `0033_sos_v2.sql` | SOS gửi kèm vị trí, tự báo lại, nhắc gọi 115 |
| `0034_preview_channel.sql` | Kênh bản thử `android_preview`, `preview_testers` |
| `0035_bp_sessions.sql` | Phiên đo theo AHA/ACC: `session_id`, `reading_no`, `context`, `rested_seconds`, `protocol_ok`, `symptoms` (cột mới đều cho null) |
| `0036_media_daily.sql` | `media_daily` + `add_media_time`: tóm tắt nghe/xem theo ngày cho người thân. **Chưa chạy trên Supabase** (chưa chạy thì tóm tắt luôn trống, app vẫn chạy) |
| `0037_demo_alerts.sql` | `demo_alert_targets`, `demo_alerts`, hàm bắn/xác nhận cảnh báo DEMO |
| `0038_demo_alert_optin.sql` | `demo_alert_join` / `demo_alert_me`: người dùng tự bật nhận cảnh báo thử |

## Gói free: cần biết

- **Không có sao lưu tự động.** Cấu trúc nằm trong migration (Git). Dữ liệu thì thỉnh thoảng xuất bằng `pg_dump`. Nâng gói khi khách trả tiền.
- **Tự tạm dừng** sau khoảng 1 tuần không hoạt động: mở app một lần trước buổi demo.
- **Dung lượng:** database 500 MB, Storage 1 GB.
- Nên có project thứ hai (free cho 2 project) để thử migration trước khi chạy lên project chính.

## Kế hoạch tiếp theo (từ 13/11; xem `FEATURES.md` cho phần đã làm)

| Bước | Thay đổi database |
|---|---|
| Tin cuối + số tin chưa đọc | Đã làm ở 0017 |
| Mã mời vào phòng | `rooms.invite_code`; hàm `join_by_code` |
| Rời phòng, đổi tên, đuổi thành viên | `room_members.role` (`owner` / `member`) |
| Gửi ảnh trong chat | Đã làm ở 0013_chat_images |
| `seed.sql` | Tài khoản và phòng mẫu cho demo |

## bp_readings (migration 0007) — theo dõi huyết áp

| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | uuid PK | |
| user_id | uuid → auth.users | mặc định `auth.uid()`, xoá user thì xoá theo |
| systolic / diastolic | smallint | 50–300 / 30–200, ràng buộc systolic > diastolic |
| pulse | smallint null | 20–250 |
| measured_at | timestamptz | mặc định now() |
| source | text | `ocr_ai` \| `ocr_local` \| `manual` |
| ocr_record_id | uuid null → ocr_records | xoá bản ghi OCR thì để null |
| note | text null | ≤ 500 ký tự |
| category | text (generated) | `normal/elevated/stage1/stage2/crisis` theo AHA 2017, tính bởi `bp_category()` |

RLS: người dùng chỉ đọc/thêm/sửa/xoá dòng của mình. Index `(user_id, measured_at desc)` cho biểu đồ, `(measured_at desc)` cho thống kê admin.
Luồng: chụp máy đo → OCR → màn "Kết quả OCR" tự nhận SYS/DIA/PULSE và hiện công tắc "Lưu vào theo dõi huyết áp" → bấm Lưu thì ghi `ocr_records` + `bp_readings`.

Cột thêm ở migration 0035 (phiên đo AHA/ACC, đều cho null): `session_id`, `reading_no` (1–3), `context` (`woke_up`/`exertion`/`caffeine_smoke`/`rested`), `rested_seconds`, `protocol_ok` (null = số đo cũ, không rõ có đủ chuẩn), `symptoms` (`chest_pain`/`short_breath`/`numb_weak`/`speech_vision`/`none`).

## Bảng mới từ 0012 đến 0038 (nhóm theo việc)

| Nhóm | Bảng |
|---|---|
| Vy | `provider_keys`, `voice_policy`, `voice_turns`, `voice_tts_log`, `voice_aliases`, `voice_prefs`, `voice_tiers`, `live_users`, `profile_phones` |
| Sức khoẻ | `health_profile`, `health_assessments`, `health_qa`, `health_feedback` |
| Thuốc | `med_plans`, `med_slots`, `med_items`, `med_prn`, `dose_events` |
| Gia đình và an toàn | `family_links`, `link_codes`, `link_attempts`, `family_audit`, `sos_events`, `emergency_cards`, `notice_log` |
| Thông báo | `device_tokens`, `push_prefs` |
| Gói | `plans`, `subscriptions`, `plan_settings` |
| Phát hành, cờ | `app_versions`, `preview_testers`, `app_flags` |
| Quản trị, hệ thống | `events`, `admin_audit`, `api_rate` |
| Giải trí | `media_daily` (chưa chạy 0036) |
| Cảnh báo DEMO | `demo_alert_targets`, `demo_alerts` |

Kiểm RLS bằng SQL: `supabase/tests/family_rls.sql`, `meds_rls.sql`, `safety_rls.sql`.
