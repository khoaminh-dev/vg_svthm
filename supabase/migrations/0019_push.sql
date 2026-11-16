-- Thông báo đẩy (FCM): mã thiết bị, cài đặt thông báo, và các trigger gọi Edge Function `push`.

create extension if not exists pg_net with schema extensions;

-- 1) Mã thiết bị. Một mã chỉ thuộc một người tại một thời điểm (đổi tài khoản trên cùng máy thì mã chuyển sang người mới).
create table if not exists public.device_tokens (
  token       text primary key check (char_length(token) between 20 and 4096),
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
create policy "dt_select_own" on public.device_tokens for select to authenticated using (user_id = auth.uid());
revoke all on public.device_tokens from public, anon, authenticated;
grant select on public.device_tokens to authenticated;

create or replace function public.register_device(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'), now())
  on conflict (token) do update set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end $$;
revoke all on function public.register_device(text, text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;

create or replace function public.unregister_device(p_token text)
returns void language sql security definer set search_path = '' as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;
revoke all on function public.unregister_device(text) from public, anon;
grant execute on function public.unregister_device(text) to authenticated;

-- 2) Cài đặt thông báo của từng người (không có dòng = mặc định: nhận tin nhắn, nhận cập nhật, không hiện nội dung).
create table if not exists public.push_prefs (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  messages   boolean not null default true,
  updates    boolean not null default true,
  show_text  boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.push_prefs enable row level security;
create policy "push_prefs_own" on public.push_prefs for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.push_prefs from public, anon;
grant select, insert, update on public.push_prefs to authenticated;

-- 3) Trigger gọi Edge Function. Địa chỉ và khoá nằm trong Vault (secret `push_url`, `push_secret`), không nằm trong mã.
create or replace function public.notify_push(p_body jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_url' limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_secret' limit 1;
  if v_url is null or v_secret is null then return; end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    body := p_body,
    timeout_milliseconds := 5000
  );
exception when others then
  null; -- thông báo lỗi thì thôi, không bao giờ làm hỏng việc gửi tin nhắn
end $$;
revoke all on function public.notify_push(jsonb) from public, anon, authenticated;

create or replace function public.trg_push_message() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify_push(jsonb_build_object(
    'type', 'message',
    'message_id', new.id,
    'room_id', new.room_id,
    'sender_id', new.user_id,
    'has_image', (new.image_path is not null),
    'content', left(coalesce(new.content, ''), 200)
  ));
  return new;
end $$;
drop trigger if exists push_on_message on public.messages;
create trigger push_on_message after insert on public.messages
  for each row execute function public.trg_push_message();

create or replace function public.trg_push_update() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.latest_build is distinct from old.latest_build and new.platform = 'android' then
    perform public.notify_push(jsonb_build_object(
      'type', 'update', 'name', new.latest_name, 'build', new.latest_build
    ));
  end if;
  return new;
end $$;
drop trigger if exists push_on_update on public.app_versions;
create trigger push_on_update after update on public.app_versions
  for each row execute function public.trg_push_update();
