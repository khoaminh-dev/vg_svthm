-- Gia đình: liên kết giữa người được chăm sóc (owner, cha mẹ) và người chăm sóc (carer, con).
-- Mọi thay đổi liên kết đi qua các hàm bên dưới; app không ghi trực tiếp vào bảng.

create table if not exists public.family_links (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  carer_id    uuid not null references auth.users(id) on delete cascade,
  relation    text not null default 'con' check (relation in ('con', 'chau', 'vo_chong', 'khac')),
  perms       jsonb not null default '{"health":true,"record_bp":true,"meds_view":true,"meds_edit":true,"location":true,"profile_edit":false,"vy_history":false,"alerts":true}'::jsonb,
  status      text not null default 'active' check (status in ('active', 'paused', 'revoked')),
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz,
  revoked_by  uuid references auth.users(id) on delete set null,
  constraint family_links_not_self check (owner_id <> carer_id),
  unique (owner_id, carer_id)
);
create index if not exists family_links_carer_idx on public.family_links (carer_id, owner_id) where status = 'active';
create index if not exists family_links_owner_idx on public.family_links (owner_id, carer_id) where status = 'active';

alter table public.family_links enable row level security;
drop policy if exists "fl_select_party" on public.family_links;
create policy "fl_select_party" on public.family_links for select to authenticated
  using (owner_id = auth.uid() or carer_id = auth.uid());
revoke all on public.family_links from public, anon, authenticated;
grant select on public.family_links to authenticated;

-- Mã mời 6 số do người được chăm sóc tạo. Chỉ lưu bản băm, dùng một lần, hết hạn sau 10 phút.
create table if not exists public.link_codes (
  id         bigint generated always as identity primary key,
  owner_id   uuid not null references auth.users(id) on delete cascade,
  code_hash  text not null,
  expires_at timestamptz not null,
  used_at    timestamptz,
  used_by    uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists link_codes_hash_idx on public.link_codes (code_hash) where used_at is null;
create index if not exists link_codes_owner_idx on public.link_codes (owner_id, created_at desc);
alter table public.link_codes enable row level security;
revoke all on public.link_codes from public, anon, authenticated;

-- Nhật ký nhập mã (chống dò mã).
create table if not exists public.link_attempts (
  id         bigint generated always as identity primary key,
  carer_id   uuid not null references auth.users(id) on delete cascade,
  ok         boolean not null,
  at         timestamptz not null default now()
);
create index if not exists link_attempts_idx on public.link_attempts (carer_id, at desc);
alter table public.link_attempts enable row level security;
revoke all on public.link_attempts from public, anon, authenticated;

-- Nhật ký gia đình: ai làm gì lúc nào. Người được chăm sóc đọc được nhật ký của mình.
create table if not exists public.family_audit (
  id        bigint generated always as identity primary key,
  owner_id  uuid not null references auth.users(id) on delete cascade,
  actor_id  uuid references auth.users(id) on delete set null,
  action    text not null,
  detail    jsonb not null default '{}'::jsonb,
  at        timestamptz not null default now()
);
create index if not exists family_audit_owner_idx on public.family_audit (owner_id, at desc);
alter table public.family_audit enable row level security;
drop policy if exists "fa_select_owner" on public.family_audit;
create policy "fa_select_owner" on public.family_audit for select to authenticated using (owner_id = auth.uid());
revoke all on public.family_audit from public, anon, authenticated;
grant select on public.family_audit to authenticated;

-- ---------- Hàm quyền (nền của mọi chính sách RLS) ----------

create or replace function public.can_view(p_owner uuid, p_kind text)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_owner = auth.uid()
      or exists (
        select 1 from public.family_links l
        where l.owner_id = p_owner and l.carer_id = auth.uid() and l.status = 'active'
          and coalesce((l.perms ->> p_kind)::boolean, false)
      );
$$;
revoke all on function public.can_view(uuid, text) from public, anon;
grant execute on function public.can_view(uuid, text) to authenticated;

-- Quyền sửa/ghi hộ: chỉ người chăm sóc có quyền tương ứng. Chủ dữ liệu tự sửa thì đã có chính sách "own" riêng.
create or replace function public.can_edit(p_owner uuid, p_kind text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.family_links l
    where l.owner_id = p_owner and l.carer_id = auth.uid() and l.status = 'active'
      and coalesce((l.perms ->> p_kind)::boolean, false)
  );
$$;
revoke all on function public.can_edit(uuid, text) from public, anon;
grant execute on function public.can_edit(uuid, text) to authenticated;

-- ---------- Ghi nhật ký ----------

create or replace function public.log_family_event(p_owner uuid, p_action text, p_detail jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  -- Chỉ ghi khi người gọi là chính chủ hoặc có liên kết đang hoạt động với chủ.
  if p_owner = auth.uid() or exists (
    select 1 from public.family_links l
    where l.owner_id = p_owner and l.carer_id = auth.uid() and l.status = 'active'
  ) then
    insert into public.family_audit (owner_id, actor_id, action, detail) values (p_owner, auth.uid(), left(p_action, 40), coalesce(p_detail, '{}'::jsonb));
  end if;
end $$;
revoke all on function public.log_family_event(uuid, text, jsonb) from public, anon;
grant execute on function public.log_family_event(uuid, text, jsonb) to authenticated;

-- ---------- Mã mời ----------

create or replace function public.create_link_code()
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_hash text;
  v_try int := 0;
  v_b bytea;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if (select count(*) from public.link_codes where owner_id = v_uid and created_at > now() - interval '1 hour') >= 6 then
    raise exception 'too_many_codes' using errcode = '54000';
  end if;
  -- Mã cũ chưa dùng của người này mất hiệu lực.
  update public.link_codes set expires_at = now() where owner_id = v_uid and used_at is null and expires_at > now();
  loop
    v_try := v_try + 1;
    v_b := extensions.gen_random_bytes(4);
    v_code := lpad(((get_byte(v_b, 0)::bigint * 16777216 + get_byte(v_b, 1)::bigint * 65536
                   + get_byte(v_b, 2)::bigint * 256 + get_byte(v_b, 3)::bigint) % 1000000)::text, 6, '0');
    v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');
    exit when not exists (select 1 from public.link_codes where code_hash = v_hash and used_at is null and expires_at > now());
    exit when v_try > 10;
  end loop;
  insert into public.link_codes (owner_id, code_hash, expires_at) values (v_uid, v_hash, now() + interval '10 minutes');
  return v_code;
end $$;
revoke all on function public.create_link_code() from public, anon;
grant execute on function public.create_link_code() to authenticated;

-- Trả về (link_id, error) thay vì ném lỗi: ném lỗi sẽ huỷ luôn dòng nhật ký nhập sai và làm chống dò mã mất tác dụng.
-- error: null | invalid_code | too_many_attempts | self_link
drop function if exists public.redeem_link_code(text, text);
create function public.redeem_link_code(p_code text, p_relation text default 'con')
returns table (link_id uuid, error text) language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_hash text;
  v_row public.link_codes;
  v_link uuid;
  v_rel text := case when p_relation in ('con', 'chau', 'vo_chong', 'khac') then p_relation else 'con' end;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if (select count(*) from public.link_attempts where carer_id = v_uid and ok = false and at > now() - interval '15 minutes') >= 8
     or (select count(*) from public.link_attempts where ok = false and at > now() - interval '1 minute') >= 60 then
    return query select null::uuid, 'too_many_attempts'::text;
    return;
  end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' then
    insert into public.link_attempts (carer_id, ok) values (v_uid, false);
    return query select null::uuid, 'invalid_code'::text;
    return;
  end if;
  v_hash := encode(extensions.digest(p_code, 'sha256'), 'hex');
  select * into v_row from public.link_codes c
    where c.code_hash = v_hash and c.used_at is null and c.expires_at > now() order by c.id desc limit 1 for update;
  if not found then
    insert into public.link_attempts (carer_id, ok) values (v_uid, false);
    return query select null::uuid, 'invalid_code'::text;
    return;
  end if;
  if v_row.owner_id = v_uid then
    return query select null::uuid, 'self_link'::text;
    return;
  end if;
  insert into public.family_links (owner_id, carer_id, relation, status)
    values (v_row.owner_id, v_uid, v_rel, 'active')
  on conflict (owner_id, carer_id) do update
    set status = 'active', relation = excluded.relation, revoked_at = null, revoked_by = null,
        perms = '{"health":true,"record_bp":true,"meds_view":true,"meds_edit":true,"location":true,"profile_edit":false,"vy_history":false,"alerts":true}'::jsonb,
        created_at = now()
  returning id into v_link;
  update public.link_codes set used_at = now(), used_by = v_uid where id = v_row.id;
  insert into public.link_attempts (carer_id, ok) values (v_uid, true);
  insert into public.family_audit (owner_id, actor_id, action, detail)
    values (v_row.owner_id, v_uid, 'link_created', jsonb_build_object('relation', v_rel));
  return query select v_link, null::text;
end $$;
revoke all on function public.redeem_link_code(text, text) from public, anon;
grant execute on function public.redeem_link_code(text, text) to authenticated;

-- ---------- Quản lý liên kết ----------

create or replace function public.revoke_link(p_link uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.family_links;
begin
  select * into v from public.family_links where id = p_link and (owner_id = auth.uid() or carer_id = auth.uid());
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update public.family_links set status = 'revoked', revoked_at = now(), revoked_by = auth.uid() where id = p_link;
  insert into public.family_audit (owner_id, actor_id, action, detail)
    values (v.owner_id, auth.uid(), case when v.owner_id = auth.uid() then 'link_revoked_by_owner' else 'link_left_by_carer' end,
            jsonb_build_object('carer_id', v.carer_id));
end $$;
revoke all on function public.revoke_link(uuid) from public, anon;
grant execute on function public.revoke_link(uuid) to authenticated;

-- Chỉ người được chăm sóc đổi quyền hoặc tạm dừng. Khoá quyền lạ bị loại bỏ.
create or replace function public.set_link_perms(p_link uuid, p_perms jsonb default null, p_status text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v public.family_links;
  k text;
  merged jsonb;
  allowed text[] := array['health', 'record_bp', 'meds_view', 'meds_edit', 'location', 'profile_edit', 'vy_history', 'alerts'];
begin
  select * into v from public.family_links where id = p_link and owner_id = auth.uid() and status <> 'revoked';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  merged := v.perms;
  if p_perms is not null then
    for k in select jsonb_object_keys(p_perms) loop
      if k = any (allowed) and jsonb_typeof(p_perms -> k) = 'boolean' then
        merged := jsonb_set(merged, array[k], p_perms -> k);
      end if;
    end loop;
  end if;
  update public.family_links
    set perms = merged, status = case when p_status in ('active', 'paused') then p_status else status end
    where id = p_link;
  insert into public.family_audit (owner_id, actor_id, action, detail)
    values (v.owner_id, auth.uid(), 'perms_changed', jsonb_build_object('carer_id', v.carer_id, 'perms', p_perms, 'status', p_status));
end $$;
revoke all on function public.set_link_perms(uuid, jsonb, text) from public, anon;
grant execute on function public.set_link_perms(uuid, jsonb, text) to authenticated;

-- Danh sách liên kết của tôi (cả hai chiều) kèm tên người kia. Không lộ liên kết đã gỡ của người khác.
create or replace function public.my_family()
returns table (
  link_id uuid, role text, other_id uuid, other_name text, other_username text, other_avatar text,
  relation text, perms jsonb, status text, created_at timestamptz
) language sql stable security definer set search_path = '' as $$
  select l.id,
         case when l.owner_id = auth.uid() then 'owner' else 'carer' end,
         p.id, p.display_name, p.username, p.avatar_url,
         l.relation, l.perms, l.status, l.created_at
  from public.family_links l
  join public.profiles p on p.id = case when l.owner_id = auth.uid() then l.carer_id else l.owner_id end
  where (l.owner_id = auth.uid() or l.carer_id = auth.uid()) and l.status <> 'revoked'
  order by l.created_at;
$$;
revoke all on function public.my_family() from public, anon;
grant execute on function public.my_family() to authenticated;

-- Dọn mã và nhật ký nhập mã cũ.
select cron.schedule('prune-link-codes', '17 4 * * *',
  $$delete from public.link_codes where created_at < now() - interval '7 days'; delete from public.link_attempts where at < now() - interval '2 days'$$);
