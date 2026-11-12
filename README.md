# vg_svthm (Viegrand)

Prototype app Flutter: đăng ký/đăng nhập, chat realtime, chụp ảnh OCR ra số liệu, điều khiển bằng giọng nói.

## Cấu trúc
- `app/` – Flutter (Riverpod, go_router, supabase_flutter, ML Kit, speech_to_text)
- `api/` – Vercel Functions (proxy Groq / ElevenLabs, có router xoay vòng key)
- `supabase/` – migration SQL (bảng + RLS)
- `docs/` – tài liệu

## Bắt đầu
1. Tạo project Flutter: `flutter create --org com.viegrand --project-name vg_svthm app`
2. Tạo project Supabase, chạy `supabase/migrations/0001_init.sql` trong SQL Editor.
3. Sao chép `.env.example`, điền biến vào Vercel (cho `api/`) và `--dart-define` (cho app).
4. Deploy `api/` lên Vercel (Root Directory = `api`), gắn domain `api.<domain>`.

## Quy ước
- Nhánh `main` ổn định; làm việc trên `feat/...`.
- Commit: `feat:`, `fix:`, `docs:`, `chore:`.
- Không commit key. Key chỉ nằm trong env.
