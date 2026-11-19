-- Quản lý khoá OpenAI trên trang admin + nền bảo mật cho Vy Live (Đợt A). Xem docs/PREMIUM_LIVE_DESIGN.md.

-- 1) provider_keys: thêm nhà cung cấp 'openai'; cho phép khoá dài hơn (bản mã hoá dài hơn bản gốc);
--    chống trùng theo dấu vân tay (bản mã hoá có IV ngẫu nhiên nên UNIQUE(provider, api_key) không còn chặn trùng được).
alter table public.provider_keys drop constraint if exists provider_keys_provider_check;
alter table public.provider_keys add constraint provider_keys_provider_check
  check (provider in ('deepseek', 'elevenlabs', 'groq', 'gemini', 'openai'));
alter table public.provider_keys drop constraint if exists provider_keys_api_key_check;
alter table public.provider_keys add constraint provider_keys_api_key_check
  check (char_length(api_key) between 8 and 900);
create unique index if not exists provider_keys_provider_fp_uniq on public.provider_keys (provider, fingerprint);

-- 2) Nhật ký thao tác admin (chỉ thêm; server ghi, không ai đọc được từ app).
create table if not exists public.admin_audit (
  id      bigint generated always as identity primary key,
  ts      timestamptz not null default now(),
  actor   text not null default 'admin' check (char_length(actor) <= 60),
  ip_hash text check (ip_hash is null or char_length(ip_hash) <= 32),   -- băm một chiều, không lưu IP thật
  action  text not null check (char_length(action) <= 60),
  target  text check (target is null or char_length(target) <= 120),
  detail  jsonb not null default '{}'::jsonb
);
create index if not exists admin_audit_ts_idx on public.admin_audit (ts desc);
alter table public.admin_audit enable row level security;
revoke all on public.admin_audit from public, anon, authenticated;
-- Chống sửa/xoá lẻ từng dòng ngay cả với service role gọi nhầm: chỉ cron dọn dữ liệu quá hạn được xoá.
create or replace function public.admin_audit_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then raise exception 'admin_audit is append-only' using errcode = '42501'; end if;
  if tg_op = 'DELETE' and old.ts > now() - interval '180 days' then
    raise exception 'admin_audit is append-only' using errcode = '42501';
  end if;
  return old;
end $$;
drop trigger if exists admin_audit_no_change on public.admin_audit;
create trigger admin_audit_no_change before update or delete on public.admin_audit
  for each row execute function public.admin_audit_immutable();
select cron.schedule('prune-admin-audit', '57 3 * * *', $$delete from public.admin_audit where ts < now() - interval '180 days'$$);

-- 3) Công tắc tắt khẩn cấp Vy Live (mặc định TẮT) và danh sách tài khoản được thử Live.
alter table public.voice_policy add column if not exists live_enabled boolean not null default false;

create table if not exists public.live_users (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  note     text not null default '' check (char_length(note) <= 60),
  added_at timestamptz not null default now()
);
alter table public.live_users enable row level security;
revoke all on public.live_users from public, anon, authenticated;
