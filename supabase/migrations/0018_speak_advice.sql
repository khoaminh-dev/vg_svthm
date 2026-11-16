-- Công tắc "Đọc lời khuyên sau khi đo" (mặc định bật). Nằm cùng bảng cài đặt cá nhân của Vy.
alter table public.voice_prefs
  add column if not exists speak_advice boolean not null default true;
