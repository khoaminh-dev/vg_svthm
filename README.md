# vg_svthm (Viegrand)

App Flutter cho người cao tuổi và người thân: chat realtime, đo và theo dõi huyết áp theo chuẩn AHA, nhắc thuốc, SOS, gia đình, trợ lý giọng nói Vy, giải trí. Tài liệu: `docs/FEATURES.md` (tính năng), `docs/ARCHITECTURE.md` (kiến trúc), `docs/APP_MAP.md` (bản đồ app cho Vy).

## Cấu trúc
- `app/` – Flutter (Riverpod, go_router, supabase_flutter, ML Kit, camera, flutter_tts, flutter_webrtc, firebase_messaging)
- `api/` – Vercel Functions (Vy, OCR, nguy cơ sức khoẻ, YouTube, cảnh báo, admin; proxy Groq / ElevenLabs / OpenAI, có router xoay vòng key)
- `supabase/` – migration SQL 0001–0038 (bảng + RLS), Edge Function `push`, kiểm RLS
- `docs/` – tài liệu

## Bắt đầu
1. Tạo project Flutter: `flutter create --org com.viegrand --project-name vg_svthm app`
2. Tạo project Supabase, chạy lần lượt các tệp trong `supabase/migrations/` (theo số thứ tự).
3. Sao chép `.env.example`, điền biến vào Vercel (cho `api/`) và `--dart-define` (cho app).
4. Deploy `api/` lên Vercel (Root Directory = `api`), gắn domain `api.<domain>`.

## Quy ước
- Nhánh `main` ổn định; làm việc trên `feat/...`.
- Commit: `feat:`, `fix:`, `docs:`, `chore:`.
- Không commit key. Key chỉ nằm trong env.
