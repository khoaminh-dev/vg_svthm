-- Voice agent: khoá API do admin quản lý, chính sách ElevenLabs, nhật ký lượt nói, bí danh, cài đặt.
-- Xem docs/VOICE_AGENT.md.

-- 1) Khoá API (chỉ service role đọc/ghi; app và anon không chạm được) --------------------------
create table if not exists public.provider_keys (
  id             uuid primary key default gen_random_uuid(),
  provider       text not null check (provider in ('deepseek', 'elevenlabs', 'groq', 'gemini')),
  label          text not null default '' check (char_length(label) <= 60),
  api_key        text not null check (char_length(api_key) between 8 and 300),
  fingerprint    text not null,                       -- 8 ký tự đầu của SHA-256, để nhận diện trong log/admin
  enabled        boolean not null default true,
  status         text not null default 'ok' check (status in ('ok', 'invalid', 'exhausted')),
  last_error     text,
  cooldown_until timestamptz,
  created_at     timestamptz not null default now(),
  unique (provider, api_key)
);
alter table public.provider_keys enable row level security;
revoke all on public.provider_keys from public, anon, authenticated;

-- 2) Chính sách (một dòng duy nhất) -------------------------------------------------------------
create table if not exists public.voice_policy (
  id                     int primary key default 1 check (id = 1),
  voice_enabled          boolean not null default true,    -- công tắc tổng của tính năng giọng nói
  eleven_enabled         boolean not null default true,    -- công tắc khẩn cấp tắt ElevenLabs
  eleven_calls_per_day   int not null default 3,
  eleven_chars_per_day   int not null default 240,
  eleven_calls_per_min   int not null default 2,
  eleven_max_chars       int not null default 80,
  eleven_global_chars_per_day int not null default 8000,   -- ngân sách chung mỗi ngày (ký tự)
  vip_multiplier         int not null default 3,
  deepseek_model         text not null default 'deepseek-flash',
  eleven_voice_id        text not null default 'EXAVITQu4vr4xnSDxMaL',
  eleven_model           text not null default 'eleven_flash_v2_5',
  turns_per_min          int not null default 10,
  turns_per_day          int not null default 150,
  updated_at             timestamptz not null default now()
);
insert into public.voice_policy (id) values (1) on conflict do nothing;
alter table public.voice_policy enable row level security;
revoke all on public.voice_policy from public, anon, authenticated;

-- 3) Hạng người dùng (admin đặt; user không tự sửa được) ----------------------------------------
create table if not exists public.voice_tiers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier    text not null check (tier in ('normal', 'vip', 'off')),
  updated_at timestamptz not null default now()
);
alter table public.voice_tiers enable row level security;
revoke all on public.voice_tiers from public, anon, authenticated;

-- 4) Cài đặt cá nhân (user tự sửa) và bí danh người nhận ---------------------------------------
create table if not exists public.voice_prefs (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  honorific  text not null default 'bác' check (honorific in ('bác', 'cô', 'chú', 'ông', 'bà', 'anh', 'chị')),
  updated_at timestamptz not null default now()
);
alter table public.voice_prefs enable row level security;
create policy "voice_prefs_own" on public.voice_prefs for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.voice_prefs from public, anon;
grant select, insert, update on public.voice_prefs to authenticated;

create table if not exists public.voice_aliases (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  alias_norm  text not null check (alias_norm ~ '^[a-z0-9 ]{1,40}$'),   -- đã bỏ dấu, viết thường
  contact_id  text not null check (char_length(contact_id) <= 80),      -- id người dùng hoặc phòng
  uses        int not null default 1,
  updated_at  timestamptz not null default now(),
  primary key (user_id, alias_norm)
);
alter table public.voice_aliases enable row level security;
create policy "voice_aliases_own" on public.voice_aliases for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.voice_aliases from public, anon;
grant select, insert, update, delete on public.voice_aliases to authenticated;

-- 5) Nhật ký từng lượt (server ghi — số đo đáng tin; không lưu nội dung lời nói) -----------------
create table if not exists public.voice_turns (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  session_id  text not null,
  turn_no     int not null default 0,
  ts          timestamptz not null default now(),
  intent      text,
  action      text,
  outcome     text,                       -- ok | error | no_speech | rate_limited
  stt_provider text, nlu_provider text, tts_mode text,
  stt_ms int, nlu_ms int, total_ms int, audio_ms int,
  tokens_in int, tokens_out int,
  stt_conf real,
  fallbacks   int not null default 0,
  error       text
);
create index if not exists voice_turns_ts_idx on public.voice_turns (ts desc);
create index if not exists voice_turns_user_idx on public.voice_turns (user_id, ts desc);
alter table public.voice_turns enable row level security;
revoke all on public.voice_turns from public, anon, authenticated;

-- Nhật ký TTS: mỗi lần quyết định dùng ElevenLabs/cache/giọng máy
create table if not exists public.voice_tts_log (
  id        bigint generated always as identity primary key,
  user_id   uuid references auth.users(id) on delete set null,
  ts        timestamptz not null default now(),
  mode      text not null,                -- eleven | cache | device
  reason    text,                         -- ok | user_calls | user_chars | user_rate | global | disabled | class | too_long | error
  chars     int not null default 0,
  key_fp    text,
  ms        int
);
create index if not exists voice_tts_log_ts_idx on public.voice_tts_log (ts desc);
alter table public.voice_tts_log enable row level security;
revoke all on public.voice_tts_log from public, anon, authenticated;

-- 6) Trừ hạn mức TTS nguyên tử (theo người dùng + ngân sách chung), ngày tính theo giờ Việt Nam ---
create or replace function public.consume_tts(
  p_user uuid, p_chars int,
  p_calls_day int, p_chars_day int, p_calls_min int, p_global_chars_day int,
  p_bypass_user boolean default false
) returns text language plpgsql security definer set search_path = '' as $$
declare
  d  timestamptz := date_trunc('day', now() at time zone 'Asia/Ho_Chi_Minh') at time zone 'Asia/Ho_Chi_Minh';
  m  timestamptz := date_trunc('minute', now());
  k_cd text := 'tts:c:d:' || p_user;
  k_xd text := 'tts:x:d:' || p_user;
  k_cm text := 'tts:c:m:' || p_user;
  k_g  text := 'tts:g:d';
  g int; cd int; xd int; cm int;
begin
  perform pg_advisory_xact_lock(hashtextextended('tts:' || p_user::text, 0));
  g := coalesce((select hits from public.api_rate where key = k_g and window_start = d), 0);
  if g + p_chars > p_global_chars_day then return 'global'; end if;

  if not p_bypass_user then
    cd := coalesce((select hits from public.api_rate where key = k_cd and window_start = d), 0);
    xd := coalesce((select hits from public.api_rate where key = k_xd and window_start = d), 0);
    cm := coalesce((select hits from public.api_rate where key = k_cm and window_start = m), 0);
    if cd + 1 > p_calls_day then return 'user_calls'; end if;
    if xd + p_chars > p_chars_day then return 'user_chars'; end if;
    if cm + 1 > p_calls_min then return 'user_rate'; end if;
    insert into public.api_rate as r (key, window_start, hits) values (k_cd, d, 1)
      on conflict (key, window_start) do update set hits = r.hits + 1;
    insert into public.api_rate as r (key, window_start, hits) values (k_xd, d, p_chars)
      on conflict (key, window_start) do update set hits = r.hits + p_chars;
    insert into public.api_rate as r (key, window_start, hits) values (k_cm, m, 1)
      on conflict (key, window_start) do update set hits = r.hits + 1;
  end if;

  insert into public.api_rate as r (key, window_start, hits) values (k_g, d, p_chars)
    on conflict (key, window_start) do update set hits = r.hits + p_chars;
  return 'ok';
end $$;
revoke all on function public.consume_tts(uuid, int, int, int, int, int, boolean) from public, anon, authenticated;
grant execute on function public.consume_tts(uuid, int, int, int, int, int, boolean) to service_role;

-- 7) Thống kê giọng nói cho admin (gom nhóm trong DB) --------------------------------------------
create or replace function public.admin_voice_stats(p_days int default 7)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  d int := least(greatest(coalesce(p_days, 7), 1), 90);
  since timestamptz := now() - make_interval(days => d);
  day0 timestamptz := date_trunc('day', now() at time zone 'Asia/Ho_Chi_Minh') at time zone 'Asia/Ho_Chi_Minh';
  res jsonb;
begin
  with
  t as (select * from public.voice_turns where ts >= since),
  l as (select * from public.voice_tts_log where ts >= since),
  who as (select id, coalesce('@' || username, display_name, left(id::text, 8)) as label from public.profiles)
  select jsonb_build_object(
    'days', d,
    'totals', jsonb_build_object(
      'turns', (select count(*) from t),
      'users', (select count(distinct user_id) from t),
      'sessions', (select count(distinct session_id) from t),
      'ok', (select count(*) from t where outcome = 'ok'),
      'errors', (select count(*) from t where outcome = 'error'),
      'noSpeech', (select count(*) from t where outcome = 'no_speech'),
      'fallbackTurns', (select count(*) from t where fallbacks > 0),
      'executed', (select count(*) from t where action = 'execute'),
      'cancelled', (select count(*) from t where action = 'cancel'),
      'asked', (select count(*) from t where action = 'ask')
    ),
    'latency', jsonb_build_object(
      'sttP50', (select round((percentile_cont(0.5) within group (order by stt_ms))::numeric) from t where stt_ms is not null),
      'sttP95', (select round((percentile_cont(0.95) within group (order by stt_ms))::numeric) from t where stt_ms is not null),
      'nluP50', (select round((percentile_cont(0.5) within group (order by nlu_ms))::numeric) from t where nlu_ms is not null),
      'nluP95', (select round((percentile_cont(0.95) within group (order by nlu_ms))::numeric) from t where nlu_ms is not null),
      'totalP50', (select round((percentile_cont(0.5) within group (order by total_ms))::numeric) from t where total_ms is not null),
      'totalP95', (select round((percentile_cont(0.95) within group (order by total_ms))::numeric) from t where total_ms is not null)
    ),
    'byIntent', coalesce((select jsonb_agg(jsonb_build_object('key', intent, 'count', c))
                          from (select intent, count(*) c from t where intent is not null group by 1 order by c desc limit 20) x), '[]'),
    'byAction', coalesce((select jsonb_agg(jsonb_build_object('key', action, 'count', c))
                          from (select action, count(*) c from t where action is not null group by 1 order by c desc) x), '[]'),
    'sttProviders', coalesce((select jsonb_agg(jsonb_build_object('key', stt_provider, 'count', c))
                          from (select stt_provider, count(*) c from t where stt_provider is not null group by 1 order by c desc) x), '[]'),
    'nluProviders', coalesce((select jsonb_agg(jsonb_build_object('key', nlu_provider, 'count', c))
                          from (select nlu_provider, count(*) c from t where nlu_provider is not null group by 1 order by c desc) x), '[]'),
    'tts', jsonb_build_object(
      'eleven', (select count(*) from l where mode = 'eleven'),
      'cache', (select count(*) from l where mode = 'cache'),
      'device', (select count(*) from l where mode = 'device'),
      'charsToday', coalesce((select sum(chars) from public.voice_tts_log where mode = 'eleven' and ts >= day0), 0),
      'byReason', coalesce((select jsonb_agg(jsonb_build_object('key', reason, 'count', c))
                          from (select reason, count(*) c from l where mode = 'device' group by 1 order by c desc) x), '[]'),
      'byKey', coalesce((select jsonb_agg(jsonb_build_object('key', key_fp, 'count', c, 'chars', ch))
                          from (select key_fp, count(*) c, sum(chars) ch from l where mode = 'eleven' and key_fp is not null group by 1 order by ch desc) x), '[]'),
      'topUsers', coalesce((select jsonb_agg(jsonb_build_object('key', label, 'count', ch))
                          from (select coalesce(w.label, left(l.user_id::text, 8)) label, sum(l.chars) ch
                                  from l left join who w on w.id = l.user_id
                                 where l.mode = 'eleven' group by 1 order by ch desc limit 10) x), '[]')
    ),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', to_char(g::date, 'YYYY-MM-DD'), 'count', coalesce(c, 0)) order by g)
                         from generate_series((now() at time zone 'utc')::date - (d - 1), (now() at time zone 'utc')::date, interval '1 day') g
                         left join (select (ts at time zone 'utc')::date as day, count(*) as c from t group by 1) x on x.day = g::date), '[]'),
    'recentErrors', coalesce((select jsonb_agg(jsonb_build_object('at', ts, 'error', error, 'intent', intent) order by ts desc)
                         from (select ts, error, intent from t where error is not null order by ts desc limit 15) x), '[]'),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', ts, 'user', label, 'intent', intent, 'action', action,
                                                         'outcome', outcome, 'ms', total_ms, 'stt', stt_provider, 'nlu', nlu_provider) order by ts desc)
                         from (select x.*, w.label from t x left join who w on w.id = x.user_id order by x.ts desc limit 30) y), '[]')
  ) into res;
  return res;
end $$;
revoke all on function public.admin_voice_stats(int) from public, anon, authenticated;
grant execute on function public.admin_voice_stats(int) to service_role;

-- Dọn dữ liệu cũ
select cron.schedule('prune-voice-turns', '37 3 * * *', $$delete from public.voice_turns where ts < now() - interval '90 days'$$);
select cron.schedule('prune-voice-tts', '47 3 * * *', $$delete from public.voice_tts_log where ts < now() - interval '90 days'$$);

-- Bucket riêng tư chứa audio các câu cố định đã tổng hợp (cache dùng chung, chỉ service role truy cập)
insert into storage.buckets (id, name, public) values ('tts-cache', 'tts-cache', false) on conflict do nothing;
