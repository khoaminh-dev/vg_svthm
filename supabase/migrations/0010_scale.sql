-- Chuẩn bị cho tải lớn (~500 người dùng):
--  * index thiếu, bỏ index thừa trên bảng ghi nhiều
--  * thống kê admin tính trong SQL (không kéo hàng chục nghìn dòng về server)
--  * giới hạn tần suất dùng chung giữa mọi instance Vercel (thay cho bộ nhớ từng instance)
--  * tự dọn dữ liệu cũ

-- 1) Index ----------------------------------------------------------------------------------
create index if not exists room_members_user_idx on public.room_members (user_id);
-- events ghi rất nhiều: bỏ index (name, created_at) vì admin gom nhóm trong khoảng thời gian đã có index created_at.
drop index if exists public.events_name_idx;

-- 2) Giới hạn tần suất / hạn mức theo cửa sổ thời gian -------------------------------------
create table if not exists public.api_rate (
  key          text        not null,
  window_start timestamptz not null,
  hits         int         not null default 0,
  primary key (key, window_start)
);
alter table public.api_rate enable row level security;
revoke all on public.api_rate from public, anon, authenticated;

-- Trả true nếu còn trong hạn mức. Nguyên tử (upsert), an toàn khi nhiều instance gọi cùng lúc.
create or replace function public.consume_rate(p_key text, p_limit int, p_window_sec int)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  w timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_sec) * p_window_sec);
  n int;
begin
  insert into public.api_rate as r (key, window_start, hits) values (p_key, w, 1)
  on conflict (key, window_start) do update set hits = r.hits + 1
  returning r.hits into n;
  return n <= p_limit;
end $$;
revoke all on function public.consume_rate(text, int, int) from public, anon, authenticated;
grant execute on function public.consume_rate(text, int, int) to service_role;

-- 3) Thống kê admin: toàn bộ gom nhóm trong DB ----------------------------------------------
create or replace function public.admin_stats(p_days int default 14)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  d     int := least(greatest(coalesce(p_days, 14), 1), 90);
  since timestamptz := now() - make_interval(days => d);
  res   jsonb;
begin
  with
  who as (
    select id, coalesce('@' || username, display_name, left(id::text, 8)) as label
      from public.profiles
  ),
  ev as (select user_id, name, screen, props, created_at from public.events where created_at >= since),
  days as (
    select g::date as day
      from generate_series((now() at time zone 'utc')::date - (d - 1), (now() at time zone 'utc')::date, interval '1 day') g
  ),
  bp as (
    select user_id, systolic, diastolic, pulse, category, source, measured_at
      from public.bp_readings where measured_at >= since
  )
  select jsonb_build_object(
    'days', d,
    'totals', jsonb_build_object(
      'users', (select count(*) from public.profiles),
      'events', (select count(*) from ev),
      'events24h', (select count(*) from public.events where created_at > now() - interval '1 day'),
      'activeUsers24h', (select count(distinct user_id) from public.events where created_at > now() - interval '1 day'),
      'activeUsers7d', (select count(distinct user_id) from public.events where created_at > now() - interval '7 days')
    ),
    'byName', coalesce((select jsonb_agg(jsonb_build_object('key', name, 'count', c))
                          from (select name, count(*) c from ev group by name order by c desc limit 30) t), '[]'),
    'byScreen', coalesce((select jsonb_agg(jsonb_build_object('key', screen, 'count', c))
                          from (select screen, count(*) c from ev where name = 'screen_view' and screen is not null
                                 group by screen order by c desc limit 20) t), '[]'),
    'byFeature', coalesce((select jsonb_agg(jsonb_build_object('key', f, 'count', c))
                          from (select props ->> 'feature' f, count(*) c from ev where name = 'tap_feature'
                                 group by 1 order by c desc limit 20) t), '[]'),
    'topUsers', coalesce((select jsonb_agg(jsonb_build_object('key', label, 'count', c))
                          from (select coalesce(w.label, left(e.user_id::text, 8)) label, count(*) c
                                  from ev e left join who w on w.id = e.user_id
                                 group by 1 order by c desc limit 10) t), '[]'),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', to_char(dd.day, 'YYYY-MM-DD'), 'count', coalesce(c, 0)) order by dd.day)
                          from days dd
                          left join (select (created_at at time zone 'utc')::date as day, count(*) as c from ev group by 1) x using (day)), '[]'),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', created_at, 'user', coalesce(label, left(user_id::text, 8)),
                                                         'name', name, 'screen', screen, 'props', props) order by created_at desc)
                          from (select e.*, w.label from ev e left join who w on w.id = e.user_id
                                 order by e.created_at desc limit 50) t), '[]'),
    'users', coalesce((select jsonb_agg(jsonb_build_object('username', username, 'name', display_name,
                                                        'joined', created_at, 'lastSeen', last_seen_at) order by created_at desc)
                          from (select username, display_name, created_at, last_seen_at from public.profiles
                                 order by created_at desc limit 200) t), '[]'),
    'bp', jsonb_build_object(
      'total', (select count(*) from bp),
      'users', (select count(distinct user_id) from bp),
      'avgSys', (select round(avg(systolic)::numeric, 1) from bp),
      'avgDia', (select round(avg(diastolic)::numeric, 1) from bp),
      'avgPulse', (select round(avg(pulse)::numeric, 1) from bp),
      'abnormal', (select count(*) from bp where category in ('stage2', 'crisis')),
      'byCategory', coalesce((select jsonb_agg(jsonb_build_object('key', category, 'count', c))
                               from (select category, count(*) c from bp group by 1 order by c desc) t), '[]'),
      'bySource', coalesce((select jsonb_agg(jsonb_build_object('key', source, 'count', c))
                               from (select source, count(*) c from bp group by 1 order by c desc) t), '[]'),
      'topUsers', coalesce((select jsonb_agg(jsonb_build_object('key', label, 'count', c))
                               from (select coalesce(w.label, left(b.user_id::text, 8)) label, count(*) c
                                       from bp b left join who w on w.id = b.user_id
                                      group by 1 order by c desc limit 10) t), '[]'),
      'daily', coalesce((select jsonb_agg(jsonb_build_object('day', to_char(dd.day, 'YYYY-MM-DD'), 'count', coalesce(c, 0), 'avgSys', a) order by dd.day)
                               from days dd
                               left join (select (measured_at at time zone 'utc')::date as day, count(*) as c, round(avg(systolic)::numeric, 1) as a
                                            from bp group by 1) x using (day)), '[]'),
      'recent', coalesce((select jsonb_agg(jsonb_build_object('at', measured_at, 'user', coalesce(label, left(user_id::text, 8)),
                                                           'sys', systolic, 'dia', diastolic, 'pulse', pulse,
                                                           'category', category, 'source', source) order by measured_at desc)
                               from (select b.*, w.label from bp b left join who w on w.id = b.user_id
                                      order by b.measured_at desc limit 30) t), '[]')
    )
  ) into res;
  return res;
end $$;
revoke all on function public.admin_stats(int) from public, anon, authenticated;
grant execute on function public.admin_stats(int) to service_role;

-- 4) Tự dọn dữ liệu cũ (pg_cron) ------------------------------------------------------------
create extension if not exists pg_cron;
select cron.schedule('prune-events', '17 3 * * *', $$delete from public.events where created_at < now() - interval '90 days'$$);
select cron.schedule('prune-api-rate', '27 3 * * *', $$delete from public.api_rate where window_start < now() - interval '3 days'$$);
