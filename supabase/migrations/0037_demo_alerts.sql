-- Cảnh báo khẩn cấp DEMO: module cảnh báo bên ngoài (camera...) gọi API, máy chủ phát push tới các tài khoản được chỉ định.
-- Chỉ phát cho tài khoản nằm trong danh sách `demo_alert_targets` (do chủ dự án tự thêm bằng SQL). Không ai khác nhận được.
-- Việc gửi do Edge Function `push` (type `demo_alert`, xem 0019_push.sql); ở đây chỉ quyết định AI nhận và chống gửi trùng.

create table if not exists public.demo_alert_targets (
  label      text primary key check (label ~ '^[a-z0-9_-]{2,30}$'),
  user_id    uuid not null references auth.users(id) on delete cascade,
  enabled    boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists demo_alert_targets_user_idx on public.demo_alert_targets (user_id);
alter table public.demo_alert_targets enable row level security;
revoke all on public.demo_alert_targets from public, anon, authenticated;

create table if not exists public.demo_alerts (
  id         uuid primary key default gen_random_uuid(),
  event_id   text not null unique,
  source     text not null,
  kind       text not null check (kind in ('fall', 'danger', 'sos', 'test')),
  message    text not null default '',
  camera     text not null default '',
  recipients int  not null default 0,
  recipient_ids uuid[] not null default '{}',
  acked_at   timestamptz,
  acked_by   uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists demo_alerts_src_idx on public.demo_alerts (source, kind, created_at desc);
alter table public.demo_alerts enable row level security;
revoke all on public.demo_alerts from public, anon, authenticated;

-- Chỉ máy chủ (service role) gọi được. Trả jsonb:
--   dry=true            : chỉ cho biết sẽ gửi cho ai, không gửi
--   error='no_target'   : không có tài khoản nào hợp lệ
--   error='cooldown'    : cùng nguồn + loại cảnh báo vừa gửi dưới 10 giây (chống bắn dồn dập)
--   duplicate=true      : event_id đã xử lý rồi (gọi lại do mất mạng), không gửi lại
create or replace function public.demo_alert_fire(
  p_event_id text, p_source text, p_kind text, p_message text, p_camera text,
  p_labels text[] default null, p_dry boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ids uuid[];
  v_labels text[];
  v_id uuid;
  v_last timestamptz;
begin
  select coalesce(array_agg(user_id), '{}'::uuid[]), coalesce(array_agg(label), '{}'::text[])
    into v_ids, v_labels
    from public.demo_alert_targets
   where enabled and (p_labels is null or label = any(p_labels));

  if p_dry then
    return jsonb_build_object('ok', true, 'dry', true, 'recipients', cardinality(v_ids), 'labels', to_jsonb(v_labels));
  end if;
  if cardinality(v_ids) = 0 then
    return jsonb_build_object('ok', false, 'error', 'no_target', 'recipients', 0);
  end if;

  if exists (select 1 from public.demo_alerts where event_id = p_event_id) then
    return jsonb_build_object('ok', true, 'duplicate', true, 'recipients', 0);
  end if;

  select max(created_at) into v_last from public.demo_alerts where source = p_source and kind = p_kind;
  if v_last is not null and v_last > now() - interval '10 seconds' then
    return jsonb_build_object('ok', false, 'error', 'cooldown', 'retry_after', 10);
  end if;

  insert into public.demo_alerts (event_id, source, kind, message, camera, recipients, recipient_ids)
  values (p_event_id, p_source, p_kind, coalesce(p_message, ''), coalesce(p_camera, ''), cardinality(v_ids), v_ids)
  on conflict (event_id) do nothing
  returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'recipients', 0);
  end if;

  perform public.notify_push(jsonb_build_object(
    'type', 'demo_alert', 'alert_id', v_id, 'kind', p_kind,
    'message', coalesce(p_message, ''), 'camera', coalesce(p_camera, ''),
    'user_ids', to_jsonb(v_ids)));

  delete from public.demo_alerts where created_at < now() - interval '7 days';
  return jsonb_build_object('ok', true, 'id', v_id, 'recipients', cardinality(v_ids), 'labels', to_jsonb(v_labels));
end $$;
revoke all on function public.demo_alert_fire(text, text, text, text, text, text[], boolean) from public, anon, authenticated;
grant execute on function public.demo_alert_fire(text, text, text, text, text, text[], boolean) to service_role;

-- ---------- Xác nhận đã nhận ----------
-- Người nhận bấm "Tôi đã nhận" trong app → ghi lại; module cảnh báo hỏi /api/alert/status để biết mà tắt chuông.
-- Người đầu tiên bấm được ghi nhận (giống ack_sos). Chỉ tài khoản nằm trong danh sách người nhận của đúng cảnh báo đó.
create or replace function public.ack_demo_alert(p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v public.demo_alerts;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into v from public.demo_alerts where id = p_id for update;
  if not found or not (auth.uid() = any(v.recipient_ids)) then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v.acked_at is not null then return 'already'; end if;
  update public.demo_alerts set acked_at = now(), acked_by = auth.uid() where id = p_id;
  return 'ok';
end $$;
revoke all on function public.ack_demo_alert(uuid) from public, anon;
grant execute on function public.ack_demo_alert(uuid) to authenticated;

-- App đọc nội dung cảnh báo để hiện màn đỏ (chỉ người nhận đọc được).
create or replace function public.demo_alert_mine(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.demo_alerts; v_by text;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into v from public.demo_alerts where id = p_id;
  if not found or not (auth.uid() = any(v.recipient_ids)) then return null; end if;
  select coalesce(nullif(trim(display_name), ''), username, 'Người thân') into v_by from public.profiles where id = v.acked_by;
  return jsonb_build_object('id', v.id, 'kind', v.kind, 'message', v.message, 'camera', v.camera,
    'created_at', v.created_at, 'acked', v.acked_at is not null, 'acked_at', v.acked_at,
    'acked_by_me', v.acked_by = auth.uid(), 'acked_by_name', v_by);
end $$;
revoke all on function public.demo_alert_mine(uuid) from public, anon;
grant execute on function public.demo_alert_mine(uuid) to authenticated;

-- Module cảnh báo hỏi trạng thái theo event_id (chỉ máy chủ gọi, qua /api/alert/status).
create or replace function public.demo_alert_status(p_event_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.demo_alerts; v_label text;
begin
  select * into v from public.demo_alerts where event_id = p_event_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select label into v_label from public.demo_alert_targets where user_id = v.acked_by order by label limit 1;
  return jsonb_build_object('ok', true, 'event_id', v.event_id, 'state', case when v.acked_at is null then 'pending' else 'acked' end,
    'acked', v.acked_at is not null, 'acked_at', v.acked_at, 'acked_by', v_label,
    'recipients', v.recipients, 'created_at', v.created_at);
end $$;
revoke all on function public.demo_alert_status(text) from public, anon, authenticated;
grant execute on function public.demo_alert_status(text) to service_role;
