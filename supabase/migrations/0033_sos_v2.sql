-- SOS gọn hơn: gửi kèm vị trí (bù sau vài giây), tự báo lại khi chưa ai nhận, nhắc chủ gọi 115.

alter table public.sos_events add column if not exists escalation smallint not null default 0;

-- Chủ gửi bù vị trí cho SOS đang mở của mình (app không chờ vị trí mới gửi SOS).
create or replace function public.update_sos_location(p_id uuid, p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'bad_location' using errcode = '22023';
  end if;
  update public.sos_events set lat = p_lat, lng = p_lng
   where id = p_id and owner_id = auth.uid() and created_at > now() - interval '1 hour';
end $$;
revoke all on function public.update_sos_location(uuid, double precision, double precision) from public, anon;
grant execute on function public.update_sos_location(uuid, double precision, double precision) to authenticated;

-- Mỗi phút: SOS mở quá 60 giây mà chưa ai nhận thì báo lại tất cả người thân (lần 1);
-- quá 180 giây vẫn chưa ai nhận thì nhắc chủ gọi 115 (lần 2). Không đụng SOS đã nhận hay đã huỷ.
create or replace function public.sos_escalate()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in
    select id, owner_id, escalation, created_at from public.sos_events
     where status = 'open' and not cancelled and escalation < 2
       and created_at < now() - interval '60 seconds' and created_at > now() - interval '30 minutes'
     for update skip locked
  loop
    if r.escalation = 0 then
      update public.sos_events set escalation = 1 where id = r.id;
      perform public.notify_push(jsonb_build_object('type', 'sos_repeat', 'sos_id', r.id, 'owner_id', r.owner_id));
    elsif r.created_at < now() - interval '180 seconds' then
      update public.sos_events set escalation = 2 where id = r.id;
      perform public.notify_push(jsonb_build_object('type', 'sos_owner', 'sos_id', r.id, 'owner_id', r.owner_id));
    end if;
  end loop;
end $$;
revoke all on function public.sos_escalate() from public, anon, authenticated;
do $$ begin perform cron.unschedule('sos-escalate'); exception when others then null; end $$;
select cron.schedule('sos-escalate', '* * * * *', 'select public.sos_escalate()');
