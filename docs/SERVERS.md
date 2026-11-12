# Thống kê server / dịch vụ

Toàn bộ chạy trên gói free. Không có server tự quản lý (không VM, không Docker).

## Tổng quan: 8 dịch vụ (6 bắt buộc, 2 dự phòng/tuỳ chọn)

| # | Dịch vụ | Vai trò | Gói | Bắt buộc | Giới hạn cần để ý |
|---|---------|---------|-----|----------|-------------------|
| 1 | **Supabase** | Auth, Postgres, Realtime (chat), Storage | Free | Có | Project bị tạm dừng sau ~1 tuần không dùng; custom domain là tính năng trả phí |
| 2 | **Vercel** | Chạy `api/` (llm, stt, tts) | Hobby | Có | Chỉ phi thương mại; function chạy ngắn, không giữ WebSocket |
| 3 | **Groq** | LLM + Whisper (STT) | Free, nhiều key | Có | Rate limit theo key; key xoay vòng qua router |
| 4 | **ElevenLabs** | TTS đọc phản hồi | Free, nhiều key | Có | Giới hạn ký tự theo tháng mỗi key |
| 5 | **GitHub** | Mã nguồn + CI (`.github/workflows/ci.yml`) | Free | Có | |
| 6 | **Domain + DNS** | `api.<domain>` trỏ về Vercel | Đã có | Có | Subdomain không giới hạn |
| 7 | **Gemini** | LLM dự phòng khi Groq hết key | Free | Tuỳ chọn | Chỉ dùng khi tất cả key Groq lỗi |
| 8 | **SMTP (Resend/Brevo)** | Gửi email xác nhận, quên mật khẩu | Free | Nên có | Email mặc định của Supabase chỉ vài email/giờ |

## Chạy trên máy người dùng (không phải server)

- Google ML Kit: OCR offline.
- `speech_to_text`: nhận giọng nói trên máy (Groq Whisper là phương án thay thế qua `/api/stt`).

## Endpoint của `api/` (Vercel)

| Endpoint | Việc | Nhà cung cấp (thứ tự thử) |
|----------|------|---------------------------|
| `/api/llm` | Parse lệnh giọng nói thành JSON hành động | Groq -> Gemini |
| `/api/stt` | Giọng nói thành text | Groq Whisper |
| `/api/tts` | Text thành giọng đọc | ElevenLabs |

Mỗi endpoint kiểm tra JWT Supabase, giới hạn 30 request/phút/user, và xoay vòng key khi gặp 401/403/429/5xx.

## Subdomain đề xuất

| Subdomain | Trỏ về |
|-----------|--------|
| `api.<domain>` | Vercel (production) |
| `staging.api.<domain>` | Vercel (preview/staging) |
| `app.<domain>` | Bản web/landing (nếu cần) |
| `no-reply@<domain>` | Địa chỉ gửi email qua SMTP |

## Biến môi trường theo dịch vụ

| Dịch vụ | Biến |
|---------|------|
| Supabase | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| Groq | `GROQ_KEYS`, `GROQ_LLM_MODEL`, `GROQ_STT_MODEL` |
| ElevenLabs | `ELEVENLABS_KEYS`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL` |
| Gemini | `GEMINI_KEYS`, `GEMINI_MODEL` |

## Khi nào phải trả tiền

Vercel Pro khi khách trả tiền (điều khoản Hobby), Supabase Pro khi cần chạy liên tục hoặc custom domain. Xem `COSTS.md`.
