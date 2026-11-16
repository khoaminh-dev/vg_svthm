-- Đơn bị thay hoặc kết thúc thì mọi lần chưa uống của nó đều bị xoá (kể cả cữ đang trong cửa sổ uống), không chỉ các lần ở tương lai.
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
    delete from public.dose_events where owner_id = p_owner and status = 'pending'
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
    delete from public.dose_events where plan_id = v_id and status = 'pending';
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
  delete from public.dose_events where plan_id = p_plan and status = 'pending';
  if v.owner_id <> auth.uid() then
    insert into public.family_audit (owner_id, actor_id, action, detail) values (v.owner_id, auth.uid(), 'edit_meds', jsonb_build_object('plan', p_plan, 'ended', true));
    perform public.notify_push(jsonb_build_object('type', 'meds_changed', 'owner_id', v.owner_id, 'carer_id', auth.uid()));
  end if;
end $$;
revoke all on function public.end_med_plan(uuid) from public, anon;
grant execute on function public.end_med_plan(uuid) to authenticated;

