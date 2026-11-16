-- Thông báo gia đình: cảnh báo huyết áp rất cao cho người chăm sóc, báo khi có người liên kết hoặc rời, "nhờ đo huyết áp".
-- Việc gửi do Edge Function `push` (xem 0019_push.sql).

alter table public.push_prefs add column if not exists family_alerts boolean not null default true;

-- Huyết áp rất cao (từ 180/120): báo người chăm sóc có quyền alerts.
create or replace function public.trg_push_bp() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.systolic >= 180 or new.diastolic >= 120 then
    perform public.notify_push(jsonb_build_object(
      'type', 'bp_alert', 'owner_id', new.user_id,
      'systolic', new.systolic, 'diastolic', new.diastolic, 'at', new.measured_at
    ));
  end if;
  return new;
end $$;
drop trigger if exists push_on_bp on public.bp_readings;
create trigger push_on_bp after insert on public.bp_readings
  for each row execute function public.trg_push_bp();

-- Có người liên kết mới, hoặc liên kết bị gỡ/rời.
create or replace function public.trg_push_link() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.status = 'active' then
    perform public.notify_push(jsonb_build_object('type', 'family_link', 'event', 'joined', 'owner_id', new.owner_id, 'carer_id', new.carer_id));
  elsif tg_op = 'UPDATE' and new.status = 'active' and old.status = 'revoked' then
    perform public.notify_push(jsonb_build_object('type', 'family_link', 'event', 'joined', 'owner_id', new.owner_id, 'carer_id', new.carer_id));
  elsif tg_op = 'UPDATE' and new.status = 'revoked' and old.status <> 'revoked' then
    perform public.notify_push(jsonb_build_object(
      'type', 'family_link', 'event', 'revoked', 'owner_id', new.owner_id, 'carer_id', new.carer_id,
      'by_owner', (new.revoked_by = new.owner_id)
    ));
  end if;
  return new;
end $$;
drop trigger if exists push_on_link on public.family_links;
create trigger push_on_link after insert or update on public.family_links
  for each row execute function public.trg_push_link();

-- Người chăm sóc nhờ người thân đo huyết áp: tối đa một lần mỗi 30 phút cho mỗi cặp.
create or replace function public.nudge_measure(p_owner uuid)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not public.can_edit(p_owner, 'health') then raise exception 'forbidden' using errcode = '42501'; end if;
  if exists (
    select 1 from public.family_audit
    where owner_id = p_owner and actor_id = auth.uid() and action = 'nudge_measure' and at > now() - interval '30 minutes'
  ) then
    return 'too_soon';
  end if;
  insert into public.family_audit (owner_id, actor_id, action) values (p_owner, auth.uid(), 'nudge_measure');
  perform public.notify_push(jsonb_build_object('type', 'nudge', 'owner_id', p_owner, 'carer_id', auth.uid()));
  return 'ok';
end $$;
revoke all on function public.nudge_measure(uuid) from public, anon;
grant execute on function public.nudge_measure(uuid) to authenticated;
