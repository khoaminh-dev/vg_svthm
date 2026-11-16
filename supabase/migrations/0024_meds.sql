-- Nhắc uống thuốc theo cách dùng ở Việt Nam: mỗi "cữ" là một túi chia sẵn (Sáng/Trưa/Chiều/Tối); thuốc bên trong là tuỳ chọn;
-- thuốc lẻ lấy từ hũ và thuốc "khi cần" có dòng riêng. Ghi/sửa đi qua các hàm bên dưới, app không ghi trực tiếp vào bảng.

-- Múi giờ của người được chăm sóc: giờ thuốc luôn theo giờ của họ (con có thể ở nước ngoài).
alter table public.profiles add column if not exists timezone text not null default 'Asia/Ho_Chi_Minh';

create table if not exists public.med_plans (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 80),
  start_date  date not null default current_date,
  end_date    date,
  recheck_date date,
  doctor      text check (doctor is null or char_length(doctor) <= 80),
  note        text check (note is null or char_length(note) <= 300),
  source      text not null default 'manual' check (source in ('manual', 'photo')),
  status      text not null default 'active' check (status in ('active', 'ended')),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint med_plans_dates check (end_date is null or end_date >= start_date)
);
create index if not exists med_plans_owner_idx on public.med_plans (owner_id, status);

create table if not exists public.med_slots (
  id              uuid primary key default gen_random_uuid(),
  plan_id         uuid not null references public.med_plans(id) on delete cascade,
  owner_id        uuid not null references auth.users(id) on delete cascade,
  label           text not null check (char_length(label) between 1 and 30),
  time_local      time not null,
  mode            text not null default 'bag' check (mode in ('bag', 'list')),
  color           text check (color is null or char_length(color) <= 20),
  meal_rel        text check (meal_rel is null or meal_rel in ('before_meal', 'after_meal', 'with_meal', 'empty', 'bedtime')),
  days_of_week    smallint[] not null default '{1,2,3,4,5,6,7}',
  window_after_min smallint not null default 120 check (window_after_min between 15 and 600),
  bags_remaining  int check (bags_remaining is null or bags_remaining >= 0),
  sort            smallint not null default 0
);
create index if not exists med_slots_plan_idx on public.med_slots (plan_id);

create table if not exists public.med_items (
  id        uuid primary key default gen_random_uuid(),
  slot_id   uuid not null references public.med_slots(id) on delete cascade,
  owner_id  uuid not null references auth.users(id) on delete cascade,
  name      text not null check (char_length(name) between 1 and 80),
  strength  text check (strength is null or char_length(strength) <= 30),
  qty       numeric(6, 2) not null default 1 check (qty > 0),
  unit      text not null default 'viên' check (unit in ('viên', 'gói', 'ml', 'đơn vị', 'giọt')),
  source    text not null default 'bag' check (source in ('bag', 'jar')),
  note      text check (note is null or char_length(note) <= 120)
);
create index if not exists med_items_slot_idx on public.med_items (slot_id);

create table if not exists public.med_prn (
  id          uuid primary key default gen_random_uuid(),
  plan_id     uuid not null references public.med_plans(id) on delete cascade,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 80),
  instruction text check (instruction is null or char_length(instruction) <= 200),
  max_per_day smallint check (max_per_day is null or max_per_day between 1 and 20)
);
create index if not exists med_prn_plan_idx on public.med_prn (plan_id);

-- Mỗi lần đến giờ uống. Giữ ảnh chụp nhãn và thuốc để lịch sử không đổi khi cữ bị sửa.
create table if not exists public.dose_events (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  plan_id     uuid references public.med_plans(id) on delete set null,
  slot_id     uuid references public.med_slots(id) on delete set null,
  slot_label  text not null,
  mode        text not null default 'bag',
  items       jsonb not null default '[]'::jsonb,
  due_date    date not null,
  due_at      timestamptz not null,
  window_end  timestamptz not null,
  status      text not null default 'pending' check (status in ('pending', 'taken', 'skipped', 'missed')),
  acted_at    timestamptz,
  acted_by    uuid references auth.users(id) on delete set null,
  snoozed_until timestamptz,
  escalation  smallint not null default 0,
  unique (slot_id, due_date)
);
create index if not exists dose_events_owner_idx on public.dose_events (owner_id, due_at);
create index if not exists dose_events_pending_idx on public.dose_events (due_at) where status = 'pending';

-- RLS: chủ xem được; người chăm sóc có quyền meds_view xem được; không ghi trực tiếp.
do $$
declare t text;
begin
  foreach t in array array['med_plans', 'med_slots', 'med_items', 'med_prn', 'dose_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s_select" on public.%I', t, t);
    execute format('create policy "%s_select" on public.%I for select to authenticated using (public.can_view(owner_id, ''meds_view''))', t, t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- Sinh các lần uống cho p_days ngày tới (kể cả hôm nay) theo múi giờ của chủ. Idempotent.
create or replace function public.gen_doses(p_owner uuid default null, p_days int default 3)
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into public.dose_events (owner_id, plan_id, slot_id, slot_label, mode, items, due_date, due_at, window_end)
  select s.owner_id, s.plan_id, s.id, s.label, s.mode,
         coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'strength', i.strength, 'qty', i.qty, 'unit', i.unit, 'source', i.source) order by i.name)
                   from public.med_items i where i.slot_id = s.id), '[]'::jsonb),
         d.day,
         (d.day + s.time_local) at time zone pr.timezone,
         ((d.day + s.time_local) at time zone pr.timezone) + make_interval(mins => s.window_after_min)
  from public.med_plans p
  join public.med_slots s on s.plan_id = p.id
  join public.profiles pr on pr.id = p.owner_id
  cross join lateral (
    select ((now() at time zone pr.timezone)::date + k) as day from generate_series(0, greatest(p_days, 0)) k
  ) d
  where p.status = 'active'
    and (p_owner is null or p.owner_id = p_owner)
    and d.day >= p.start_date and (p.end_date is null or d.day <= p.end_date)
    and extract(isodow from d.day)::smallint = any (s.days_of_week)
  on conflict (slot_id, due_date) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.gen_doses(uuid, int) from public, anon, authenticated;

-- Việc định kỳ: sinh lịch, đánh dấu "chưa uống" khi quá cửa sổ, kết thúc đơn đã hết hạn.
create or replace function public.maintain_doses()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.med_plans p set status = 'ended', updated_at = now()
    from public.profiles pr
    where pr.id = p.owner_id and p.status = 'active' and p.end_date is not null
      and p.end_date < (now() at time zone pr.timezone)::date;
  perform public.gen_doses(null, 3);
  update public.dose_events set status = 'missed' where status = 'pending' and window_end < now();
  delete from public.dose_events where due_at < now() - interval '90 days';
end $$;
revoke all on function public.maintain_doses() from public, anon, authenticated;
select cron.schedule('meds-maintain', '*/10 * * * *', 'select public.maintain_doses()');

-- ---------- Ghi/sửa đơn thuốc ----------

create or replace function public.save_med_plan(p_owner uuid, p_plan jsonb, p_replace boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := nullif(p_plan ->> 'id', '')::uuid;
  v_slot jsonb;
  v_item jsonb;
  v_prn jsonb;
  v_slot_id uuid;
  v_i int := 0;
  v_start date := coalesce(nullif(p_plan ->> 'start_date', '')::date, current_date);
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_owner <> auth.uid() and not public.can_edit(p_owner, 'meds_edit') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_plan -> 'slots', '[]'::jsonb)) > 8 then raise exception 'too_many_slots' using errcode = '22023'; end if;
  if jsonb_array_length(coalesce(p_plan -> 'prn', '[]'::jsonb)) > 10 then raise exception 'too_many_prn' using errcode = '22023'; end if;

  if p_replace then
    delete from public.dose_events where owner_id = p_owner and status = 'pending' and due_at > now()
      and plan_id in (select id from public.med_plans where owner_id = p_owner and status = 'active' and id is distinct from v_id);
    update public.med_plans set status = 'ended', updated_at = now()
      where owner_id = p_owner and status = 'active' and id is distinct from v_id;
  end if;

  if v_id is not null then
    if not exists (select 1 from public.med_plans where id = v_id and owner_id = p_owner) then
      raise exception 'not_found' using errcode = 'P0002';
    end if;
    update public.med_plans set
      title = p_plan ->> 'title', start_date = v_start,
      end_date = nullif(p_plan ->> 'end_date', '')::date, recheck_date = nullif(p_plan ->> 'recheck_date', '')::date,
      doctor = nullif(p_plan ->> 'doctor', ''), note = nullif(p_plan ->> 'note', ''),
      status = 'active', updated_at = now()
    where id = v_id;
    delete from public.dose_events where plan_id = v_id and status = 'pending' and due_at > now();
    delete from public.med_slots where plan_id = v_id;
    delete from public.med_prn where plan_id = v_id;
  else
    insert into public.med_plans (owner_id, title, start_date, end_date, recheck_date, doctor, note, source, created_by)
    values (p_owner, p_plan ->> 'title', v_start, nullif(p_plan ->> 'end_date', '')::date, nullif(p_plan ->> 'recheck_date', '')::date,
            nullif(p_plan ->> 'doctor', ''), nullif(p_plan ->> 'note', ''),
            case when p_plan ->> 'source' = 'photo' then 'photo' else 'manual' end, auth.uid())
    returning id into v_id;
  end if;

  for v_slot in select * from jsonb_array_elements(coalesce(p_plan -> 'slots', '[]'::jsonb)) loop
    insert into public.med_slots (plan_id, owner_id, label, time_local, mode, color, meal_rel, days_of_week, window_after_min, bags_remaining, sort)
    values (v_id, p_owner, v_slot ->> 'label', (v_slot ->> 'time')::time,
            case when v_slot ->> 'mode' = 'list' then 'list' else 'bag' end,
            nullif(v_slot ->> 'color', ''), nullif(v_slot ->> 'meal_rel', ''),
            coalesce((select array_agg(x::smallint) from jsonb_array_elements_text(v_slot -> 'days_of_week') x), '{1,2,3,4,5,6,7}'::smallint[]),
            coalesce(nullif(v_slot ->> 'window_after_min', '')::smallint, 120),
            nullif(v_slot ->> 'bags_remaining', '')::int, v_i)
    returning id into v_slot_id;
    v_i := v_i + 1;
    for v_item in select * from jsonb_array_elements(coalesce(v_slot -> 'items', '[]'::jsonb)) loop
      insert into public.med_items (slot_id, owner_id, name, strength, qty, unit, source, note)
      values (v_slot_id, p_owner, v_item ->> 'name', nullif(v_item ->> 'strength', ''),
              coalesce(nullif(v_item ->> 'qty', '')::numeric, 1), coalesce(nullif(v_item ->> 'unit', ''), 'viên'),
              case when v_item ->> 'source' = 'jar' then 'jar' else 'bag' end, nullif(v_item ->> 'note', ''));
    end loop;
  end loop;

  for v_prn in select * from jsonb_array_elements(coalesce(p_plan -> 'prn', '[]'::jsonb)) loop
    insert into public.med_prn (plan_id, owner_id, name, instruction, max_per_day)
    values (v_id, p_owner, v_prn ->> 'name', nullif(v_prn ->> 'instruction', ''), nullif(v_prn ->> 'max_per_day', '')::smallint);
  end loop;

  perform public.gen_doses(p_owner, 3);
  -- Cữ hôm nay đã qua giờ khi đơn mới tạo thì không tính là "chưa uống".
  update public.dose_events set status = 'skipped', acted_at = now(), acted_by = auth.uid()
    where owner_id = p_owner and plan_id = v_id and status = 'pending' and window_end < now();

  if p_owner <> auth.uid() then
    insert into public.family_audit (owner_id, actor_id, action, detail) values (p_owner, auth.uid(), 'edit_meds', jsonb_build_object('plan', v_id));
    perform public.notify_push(jsonb_build_object('type', 'meds_changed', 'owner_id', p_owner, 'carer_id', auth.uid()));
  end if;
  return v_id;
end $$;
revoke all on function public.save_med_plan(uuid, jsonb, boolean) from public, anon;
grant execute on function public.save_med_plan(uuid, jsonb, boolean) to authenticated;

create or replace function public.end_med_plan(p_plan uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.med_plans;
begin
  select * into v from public.med_plans where id = p_plan;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v.owner_id <> auth.uid() and not public.can_edit(v.owner_id, 'meds_edit') then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.med_plans set status = 'ended', updated_at = now() where id = p_plan;
  delete from public.dose_events where plan_id = p_plan and status = 'pending' and due_at > now();
  if v.owner_id <> auth.uid() then
    insert into public.family_audit (owner_id, actor_id, action, detail) values (v.owner_id, auth.uid(), 'edit_meds', jsonb_build_object('plan', p_plan, 'ended', true));
    perform public.notify_push(jsonb_build_object('type', 'meds_changed', 'owner_id', v.owner_id, 'carer_id', auth.uid()));
  end if;
end $$;
revoke all on function public.end_med_plan(uuid) from public, anon;
grant execute on function public.end_med_plan(uuid) to authenticated;

-- ---------- Ghi nhận uống ----------

-- status: taken | skipped | pending (hoàn tác trong 2 giờ). p_snooze_min: nhắc lại sau N phút (chỉ chính chủ).
create or replace function public.set_dose(p_event uuid, p_status text default null, p_snooze_min int default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.dose_events;
begin
  select * into v from public.dose_events where id = p_event;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v.owner_id <> auth.uid() and not public.can_edit(v.owner_id, 'meds_edit') then raise exception 'forbidden' using errcode = '42501'; end if;

  if p_snooze_min is not null then
    if v.owner_id <> auth.uid() or v.status <> 'pending' then raise exception 'forbidden' using errcode = '42501'; end if;
    update public.dose_events set snoozed_until = now() + make_interval(mins => least(greatest(p_snooze_min, 5), 60)), escalation = 0 where id = p_event;
    return;
  end if;

  if p_status = 'taken' or p_status = 'skipped' then
    if v.status in ('taken', 'skipped') then return; end if;
    update public.dose_events set status = p_status, acted_at = now(), acted_by = auth.uid(), snoozed_until = null where id = p_event;
    if p_status = 'taken' and v.slot_id is not null then
      update public.med_slots set bags_remaining = greatest(bags_remaining - 1, 0) where id = v.slot_id and bags_remaining is not null;
    end if;
  elsif p_status = 'pending' then
    if v.status not in ('taken', 'skipped') or v.acted_at is null or v.acted_at < now() - interval '2 hours' then
      raise exception 'cannot_undo' using errcode = '22023';
    end if;
    update public.dose_events set status = 'pending', acted_at = null, acted_by = null where id = p_event;
    if v.status = 'taken' and v.slot_id is not null then
      update public.med_slots set bags_remaining = bags_remaining + 1 where id = v.slot_id and bags_remaining is not null;
    end if;
  else
    raise exception 'bad_status' using errcode = '22023';
  end if;
end $$;
revoke all on function public.set_dose(uuid, text, int) from public, anon;
grant execute on function public.set_dose(uuid, text, int) to authenticated;
