# Kiến trúc

Flutter app ──► Supabase (Auth, Postgres, Realtime, Storage)   # chat, auth, dữ liệu OCR
            └─► Vercel `api.<domain>` ──► Router xoay vòng ──► Groq (LLM, STT) / ElevenLabs (TTS) / Gemini (dự phòng)

- OCR chạy trên máy (Google ML Kit), app tách số liệu rồi lưu vào `ocr_records`.
- Voice: STT (máy hoặc /api/stt) -> /api/llm parse lệnh thành JSON -> app thực thi -> /api/tts đọc phản hồi.
- Router: mỗi nhà cung cấp có một key pool; gặp 401/403/429/5xx thì đánh dấu key nghỉ và thử key kế tiếp.
