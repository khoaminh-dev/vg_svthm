-- Phiên đo huyết áp theo chuẩn AHA/ACC: 2 số cách nhau 1 phút, ngồi nghỉ yên 5 phút trước khi đo.
-- Tất cả cột mới cho phép null: số đo cũ không rõ có đủ chuẩn hay không (protocol_ok null), không bị coi là đủ chuẩn.
alter table public.bp_readings
  add column if not exists session_id    uuid,
  add column if not exists reading_no    smallint check (reading_no between 1 and 3),
  add column if not exists context       text[] check (context <@ array['woke_up','exertion','caffeine_smoke','rested']::text[]),
  add column if not exists rested_seconds integer check (rested_seconds between 0 and 7200),
  add column if not exists protocol_ok   boolean,
  add column if not exists symptoms      text[] check (symptoms <@ array['chest_pain','short_breath','numb_weak','speech_vision','none']::text[]);

create index if not exists bp_readings_session_idx on public.bp_readings (session_id) where session_id is not null;

-- Trung bình theo phiên: chỉ tính số đủ chuẩn nếu phiên có số đủ chuẩn, ngược lại tính tất cả.
create or replace view public.bp_sessions_v with (security_invoker = true) as
select
  r.user_id,
  coalesce(r.session_id, r.id)                          as session_id,
  min(r.measured_at)                                    as started_at,
  count(*)                                              as readings,
  round(avg(r.systolic))::smallint                      as avg_systolic,
  round(avg(r.diastolic))::smallint                     as avg_diastolic,
  public.bp_category(round(avg(r.systolic))::int, round(avg(r.diastolic))::int) as category_avg,
  coalesce(bool_or(r.protocol_ok), false)               as protocol_ok
from public.bp_readings r
group by r.user_id, coalesce(r.session_id, r.id);

grant select on public.bp_sessions_v to authenticated;
revoke all on public.bp_sessions_v from anon;
