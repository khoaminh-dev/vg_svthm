-- Tóm tắt nghe/xem giải trí theo ngày: để người thân (đã được cấp quyền "xem lịch sử hỏi Vy") biết cha/mẹ hay nghe gì và bao lâu.
-- CHỈ lưu thể loại (từ khoá như "nhạc xưa") và số giây, KHÔNG lưu tên bài, không ghi âm, không lưu lời nói.
-- Người cao tuổi tắt "Nhớ những gì tôi đã nghe" thì app không gửi gì lên đây.
--
-- Quyền:
--   đọc : chính chủ, và người thân đang liên kết có quyền vy_history (mặc định TẮT, chủ bật ở màn quản lý quyền)
--   ghi : chỉ chính chủ, qua hàm add_media_time
create table if not exists public.media_daily (
  user_id    uuid    not null references auth.users (id) on delete cascade,
  day        date    not null,
  topic      text    not null check (char_length(topic) between 1 and 60),
  seconds    integer not null default 0 check (seconds between 0 and 86400),
  plays      integer not null default 0 check (plays between 0 and 1000),
  updated_at timestamptz not null default now(),
  primary key (user_id, day, topic)
);

create index if not exists media_daily_day_idx on public.media_daily (day);

alter table public.media_daily enable row level security;

revoke all on public.media_daily from anon;
grant select, insert, update, delete on public.media_daily to authenticated;

drop policy if exists media_daily_select on public.media_daily;
create policy media_daily_select on public.media_daily
  for select to authenticated
  using (user_id = auth.uid() or public.can_view(user_id, 'vy_history'));

drop policy if exists media_daily_insert on public.media_daily;
create policy media_daily_insert on public.media_daily
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists media_daily_update on public.media_daily;
create policy media_daily_update on public.media_daily
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists media_daily_delete on public.media_daily;
create policy media_daily_delete on public.media_daily
  for delete to authenticated
  using (user_id = auth.uid());

-- Cộng dồn thời gian nghe của hôm nay (giờ Việt Nam). Chạy với quyền người gọi nên vẫn bị RLS chặn nếu không phải chính chủ.
create or replace function public.add_media_time(p_topic text, p_seconds integer, p_plays integer default 0)
returns void
language plpgsql
set search_path = public
as $$
declare
  t text := left(btrim(coalesce(p_topic, '')), 60);
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if t = '' or p_seconds is null or p_seconds < 0 or p_seconds > 14400 then
    return;
  end if;
  insert into public.media_daily as m (user_id, day, topic, seconds, plays)
  values (auth.uid(), (now() at time zone 'Asia/Ho_Chi_Minh')::date, t, p_seconds, greatest(coalesce(p_plays, 0), 0))
  on conflict (user_id, day, topic) do update
    set seconds    = least(m.seconds + excluded.seconds, 86400),
        plays      = least(m.plays + excluded.plays, 1000),
        updated_at = now();
end;
$$;

revoke all on function public.add_media_time(text, integer, integer) from public, anon;
grant execute on function public.add_media_time(text, integer, integer) to authenticated;

-- Xoá tóm tắt cũ hơn 60 ngày khi có ai ghi mới (đỡ cần tác vụ định kỳ riêng).
create or replace function public.media_daily_prune()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  delete from public.media_daily where user_id = new.user_id and day < (now() at time zone 'Asia/Ho_Chi_Minh')::date - 60;
  return null;
end;
$$;

drop trigger if exists media_daily_prune on public.media_daily;
create trigger media_daily_prune
  after insert on public.media_daily
  for each row execute function public.media_daily_prune();
