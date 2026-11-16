-- Giai đoạn 4: lưới an toàn thuốc, SOS, thẻ y tế khẩn cấp, tóm tắt cuối ngày, nhắc sắp hết/tái khám, giờ yên tĩnh.
-- Việc gửi do Edge Function `push` (xem 0019_push.sql); ở đây chỉ quyết định AI nhận GÌ và KHI NÀO.

-- ---------- Cài đặt thông báo mở rộng ----------
alter table public.push_prefs
  add column if not exists dose_alerts boolean not null default true,
  add column if not exists digest boolean not null default false,
  add column if not exists quiet_start time,
  add column if not exists quiet_end time;

-- ---------- Chống gửi trùng ----------
create table if not exists public.notice_log (
  owner_id uuid not null references auth.users(id) on delete cascade,
  kind     text not null,
  ref      text not null default '',
  day      date not null,
  primary key (owner_id, kind, ref, day)
);
alter table public.notice_log enable row level security;
revoke all on public.notice_log from public, anon, authenticated;

-- true nếu đây là lần đầu trong ngày (và ghi nhận luôn).
create or replace function public.notice_once(p_owner uuid, p_kind text, p_ref text, p_day date)
returns boolean language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into public.notice_log (owner_id, kind, ref, day) values (p_owner, p_kind, coalesce(p_ref, ''), p_day)
    on conflict do nothing;
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.notice_once(uuid, text, text, date) from public, anon, authenticated;

-- ---------- Lưới an toàn thuốc ----------
-- Quá 45 phút: báo con. Quá 15 phút: nhắc cha mẹ. Gộp theo người để không dồn dập.
create or replace function public.meds_escalate()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in
    with due as (
      update public.dose_events d set escalation = 2
       where d.status = 'pending' and d.escalation < 2 and d.window_end > now()
         and now() >= d.due_at + interval '45 minutes'
         and (d.snoozed_until is null or d.snoozed_until <= now())
      returning d.owner_id, d.slot_label, d.due_at
    )
    select owner_id, jsonb_agg(jsonb_build_object('label', slot_label, 'at', due_at) order by due_at) as doses
      from due group by owner_id
  loop
    perform public.notify_push(jsonb_build_object('type', 'dose_missed', 'owner_id', r.owner_id, 'doses', r.doses));
  end loop;

  for r in
    with due as (
      update public.dose_events d set escalation = 1
       where d.status = 'pending' and d.escalation = 0 and d.window_end > now()
         and now() >= d.due_at + interval '15 minutes'
         and (d.snoozed_until is null or d.snoozed_until <= now())
      returning d.owner_id, d.slot_label, d.due_at
    )
    select owner_id, jsonb_agg(jsonb_build_object('label', slot_label, 'at', due_at) order by due_at) as doses
      from due group by owner_id
  loop
    perform public.notify_push(jsonb_build_object('type', 'dose_nudge', 'owner_id', r.owner_id, 'doses', r.doses));
  end loop;
end $$;
revoke all on function public.meds_escalate() from public, anon, authenticated;
do $$ begin perform cron.unschedule('meds-escalate'); exception when others then null; end $$;
select cron.schedule('meds-escalate', '* * * * *', 'select public.meds_escalate()');

-- ---------- Tóm tắt cuối ngày, nhắc sắp hết túi và tái khám ----------
create or replace function public.family_daily()
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record; v_local timestamp; v_day date; v_sys int; v_dia int; v_taken int; v_total int; v_text text; q record;
begin
  for r in
    select distinct l.owner_id, coalesce(pr.timezone, 'Asia/Ho_Chi_Minh') as tz
      from public.family_links l join public.profiles pr on pr.id = l.owner_id
     where l.status = 'active'
  loop
    v_local := now() at time zone r.tz;
    v_day := v_local::date;

    -- 20:00-20:30: tóm tắt ngày
    if v_local::time >= time '20:00' and v_local::time < time '20:30'
       and public.notice_once(r.owner_id, 'digest', '', v_day) then
      select systolic, diastolic into v_sys, v_dia from public.bp_readings
        where user_id = r.owner_id and measured_at >= (v_day::timestamp at time zone r.tz)
        order by measured_at desc limit 1;
      select count(*) filter (where status = 'taken'), count(*) into v_taken, v_total
        from public.dose_events where owner_id = r.owner_id and due_date = v_day and status <> 'skipped';
      v_text := 'Hôm nay: ' || case when v_sys is null then 'chưa đo huyết áp' else v_sys || '/' || v_dia end
             || case when v_total > 0 then ', uống ' || v_taken || '/' || v_total || ' cữ' else '' end || '.';
      perform public.notify_push(jsonb_build_object('type', 'digest', 'owner_id', r.owner_id, 'text', v_text));
    end if;

    -- 09:00-09:30: sắp hết túi (còn đúng 3) và sắp tái khám (còn 2 ngày)
    if v_local::time >= time '09:00' and v_local::time < time '09:30' then
      for q in
        select p.id as plan_id, p.title, p.recheck_date from public.med_plans p
         where p.owner_id = r.owner_id and p.status = 'active' and p.recheck_date = v_day + 2
      loop
        if public.notice_once(r.owner_id, 'recheck', q.plan_id::text, v_day) then
          perform public.notify_push(jsonb_build_object('type', 'med_reminder', 'kind', 'recheck', 'owner_id', r.owner_id,
            'title', q.title, 'date', q.recheck_date));
        end if;
      end loop;
      for q in
        select s.id as slot_id, s.label, p.title from public.med_slots s join public.med_plans p on p.id = s.plan_id
         where s.owner_id = r.owner_id and p.status = 'active' and s.bags_remaining = 3
      loop
        if public.notice_once(r.owner_id, 'low_stock', q.slot_id::text || ':3', v_day) then
          perform public.notify_push(jsonb_build_object('type', 'med_reminder', 'kind', 'low_stock', 'owner_id', r.owner_id,
            'title', q.title, 'label', q.label));
        end if;
      end loop;
    end if;
  end loop;
  delete from public.notice_log where day < current_date - 7;
end $$;
revoke all on function public.family_daily() from public, anon, authenticated;
do $$ begin perform cron.unschedule('family-daily'); exception when others then null; end $$;
select cron.schedule('family-daily', '*/10 * * * *', 'select public.family_daily()');

-- ---------- SOS ----------
create table if not exists public.sos_events (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  lat        double precision,
  lng        double precision,
  status     text not null default 'open' check (status in ('open', 'handled')),
  handled_by uuid references auth.users(id) on delete set null,
  handled_at timestamptz,
  cancelled  boolean not null default false
);
create index if not exists sos_events_owner_idx on public.sos_events (owner_id, created_at desc);
alter table public.sos_events enable row level security;
drop policy if exists "sos_select" on public.sos_events;
create policy "sos_select" on public.sos_events for select to authenticated using (public.can_view(owner_id, 'alerts'));
revoke all on public.sos_events from public, anon, authenticated;
grant select on public.sos_events to authenticated;

-- Chủ bấm SOS. Trong 2 phút chỉ có một SOS đang mở (bấm lại trả về cái cũ, không gửi lại).
create or replace function public.trigger_sos(p_lat double precision default null, p_lng double precision default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select id into v_id from public.sos_events
   where owner_id = auth.uid() and status = 'open' and created_at > now() - interval '2 minutes'
   order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.sos_events (owner_id, lat, lng) values (auth.uid(), p_lat, p_lng) returning id into v_id;
  perform public.notify_push(jsonb_build_object('type', 'sos', 'sos_id', v_id, 'owner_id', auth.uid()));
  return v_id;
end $$;
revoke all on function public.trigger_sos(double precision, double precision) from public, anon;
grant execute on function public.trigger_sos(double precision, double precision) to authenticated;

-- Con (có alerts) bấm "Tôi đã nhận": người đầu tiên được ghi nhận, những người còn lại thấy tên người đó.
create or replace function public.ack_sos(p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v public.sos_events;
begin
  select * into v from public.sos_events where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.can_edit(v.owner_id, 'alerts') then raise exception 'forbidden' using errcode = '42501'; end if;
  if v.status = 'handled' then return 'already'; end if;
  update public.sos_events set status = 'handled', handled_by = auth.uid(), handled_at = now() where id = p_id;
  perform public.notify_push(jsonb_build_object('type', 'sos_ack', 'event', 'acked', 'sos_id', p_id,
    'owner_id', v.owner_id, 'carer_id', auth.uid()));
  return 'ok';
end $$;
revoke all on function public.ack_sos(uuid) from public, anon;
grant execute on function public.ack_sos(uuid) to authenticated;

-- Chủ huỷ khi bấm nhầm.
create or replace function public.cancel_sos(p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v public.sos_events;
begin
  select * into v from public.sos_events where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v.owner_id <> auth.uid() then raise exception 'forbidden' using errcode = '42501'; end if;
  if v.status = 'handled' then return 'already'; end if;
  update public.sos_events set status = 'handled', handled_by = auth.uid(), handled_at = now(), cancelled = true where id = p_id;
  perform public.notify_push(jsonb_build_object('type', 'sos_ack', 'event', 'cancelled', 'sos_id', p_id, 'owner_id', v.owner_id));
  return 'ok';
end $$;
revoke all on function public.cancel_sos(uuid) from public, anon;
grant execute on function public.cancel_sos(uuid) to authenticated;

-- ---------- Thẻ y tế khẩn cấp ----------
create table if not exists public.emergency_cards (
  owner_id   uuid primary key references auth.users(id) on delete cascade,
  blood_type text,
  allergies  text,
  conditions text,
  own_phone  text,
  contacts   jsonb not null default '[]'::jsonb,
  note       text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.emergency_cards enable row level security;
drop policy if exists "emergency_select" on public.emergency_cards;
create policy "emergency_select" on public.emergency_cards for select to authenticated
  using (public.can_view(owner_id, 'health') or public.can_view(owner_id, 'alerts'));
revoke all on public.emergency_cards from public, anon, authenticated;
grant select on public.emergency_cards to authenticated;

create or replace function public.save_emergency_card(p_owner uuid, p_card jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_blood text := nullif(trim(coalesce(p_card ->> 'blood_type', '')), '');
  v_contacts jsonb := '[]'::jsonb;
  c jsonb;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_owner <> auth.uid() and not public.can_edit(p_owner, 'profile_edit') then raise exception 'forbidden' using errcode = '42501'; end if;
  if v_blood is not null and v_blood not in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') then
    raise exception 'bad_blood_type' using errcode = '22023';
  end if;
  for c in select * from jsonb_array_elements(coalesce(p_card -> 'contacts', '[]'::jsonb)) loop
    if length(trim(coalesce(c ->> 'phone', ''))) > 0 then
      if length(c ->> 'phone') > 20 or (c ->> 'phone') !~ '^[0-9+ .\-]+$' then raise exception 'bad_phone' using errcode = '22023'; end if;
      v_contacts := v_contacts || jsonb_build_array(jsonb_build_object(
        'name', left(trim(coalesce(c ->> 'name', '')), 40), 'phone', trim(c ->> 'phone')));
    end if;
    exit when jsonb_array_length(v_contacts) >= 3;
  end loop;
  if length(coalesce(p_card ->> 'own_phone', '')) > 20 or coalesce(p_card ->> 'own_phone', '') !~ '^[0-9+ .\-]*$' then
    raise exception 'bad_phone' using errcode = '22023';
  end if;
  insert into public.emergency_cards (owner_id, blood_type, allergies, conditions, own_phone, contacts, note, updated_at, updated_by)
  values (p_owner, v_blood,
          nullif(left(trim(coalesce(p_card ->> 'allergies', '')), 300), ''),
          nullif(left(trim(coalesce(p_card ->> 'conditions', '')), 300), ''),
          nullif(trim(coalesce(p_card ->> 'own_phone', '')), ''),
          v_contacts,
          nullif(left(trim(coalesce(p_card ->> 'note', '')), 300), ''),
          now(), auth.uid())
  on conflict (owner_id) do update set blood_type = excluded.blood_type, allergies = excluded.allergies,
    conditions = excluded.conditions, own_phone = excluded.own_phone, contacts = excluded.contacts, note = excluded.note,
    updated_at = now(), updated_by = auth.uid();
  if p_owner <> auth.uid() then
    insert into public.family_audit (owner_id, actor_id, action) values (p_owner, auth.uid(), 'edit_emergency_card');
  end if;
end $$;
revoke all on function public.save_emergency_card(uuid, jsonb) from public, anon;
grant execute on function public.save_emergency_card(uuid, jsonb) to authenticated;
