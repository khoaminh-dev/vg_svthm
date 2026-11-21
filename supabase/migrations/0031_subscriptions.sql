-- Gói Vy Live: người chăm sóc (con) mua, người được chăm sóc (cha mẹ) hưởng qua family_links.
-- Thanh toán xử lý ngoài app; admin bấm "Xác nhận đã thanh toán" thì gói mới có hiệu lực. App không ghi trực tiếp.

create table if not exists public.plans (
  id        uuid primary key default gen_random_uuid(),
  name      text not null check (char_length(name) between 1 and 60),
  price_vnd integer not null default 0 check (price_vnd >= 0 and price_vnd <= 100000000),
  days      integer not null check (days between 1 and 3660),
  active    boolean not null default false,   -- chỉ gói đang bật và có giá mới hiện cho người dùng
  sort      integer not null default 0,
  note      text not null default '' check (char_length(note) <= 200),
  created_at timestamptz not null default now()
);
alter table public.plans enable row level security;
revoke all on public.plans from public, anon, authenticated;
grant select on public.plans to authenticated;
drop policy if exists "plans_read_active" on public.plans;
create policy "plans_read_active" on public.plans for select to authenticated using (active and price_vnd > 0);

insert into public.plans (name, price_vnd, days, active, sort, note)
select * from (values
  ('Gói tháng', 0, 30,  false, 1, ''),
  ('Gói quý',   0, 90,  false, 2, ''),
  ('Gói năm',   0, 365, false, 3, '')
) as v(name, price_vnd, days, active, sort, note)
where not exists (select 1 from public.plans);

-- Một dòng cấu hình: hướng dẫn thanh toán hiện trong app dưới mã đơn.
create table if not exists public.plan_settings (
  id       smallint primary key default 1 check (id = 1),
  pay_note text not null default 'Sau khi đặt, hãy chuyển khoản theo hướng dẫn của Viegrand và ghi mã đơn. Gói sẽ bật khi Viegrand xác nhận đã nhận tiền.' check (char_length(pay_note) <= 600)
);
insert into public.plan_settings (id) values (1) on conflict do nothing;
alter table public.plan_settings enable row level security;
revoke all on public.plan_settings from public, anon, authenticated;

create table if not exists public.subscriptions (
  id           uuid primary key default gen_random_uuid(),
  payer_id     uuid not null references auth.users(id) on delete cascade,
  plan_id      uuid references public.plans(id) on delete set null,
  plan_name    text not null,
  price_vnd    integer not null,
  days         integer not null,
  order_code   text not null unique,
  status       text not null default 'pending' check (status in ('pending', 'active', 'expired', 'cancelled')),
  admin_note   text not null default '' check (char_length(admin_note) <= 200),
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,
  expires_at   timestamptz
);
create index if not exists subscriptions_payer_idx on public.subscriptions (payer_id, created_at desc);
create index if not exists subscriptions_status_idx on public.subscriptions (status, created_at desc);
alter table public.subscriptions enable row level security;
revoke all on public.subscriptions from public, anon, authenticated;
grant select on public.subscriptions to authenticated;
drop policy if exists "subs_read_own" on public.subscriptions;
create policy "subs_read_own" on public.subscriptions for select to authenticated using (payer_id = auth.uid());

-- Tạo đơn: người dùng chọn gói. Mỗi người chỉ một đơn chờ; tối đa 5 đơn mỗi ngày.
create or replace function public.request_subscription(p_plan uuid) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  me uuid := auth.uid();
  pl public.plans;
  existing public.subscriptions;
  code text;
  s public.subscriptions;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into pl from public.plans where id = p_plan and active and price_vnd > 0;
  if not found then raise exception 'plan_unavailable' using errcode = 'P0001'; end if;
  select * into existing from public.subscriptions where payer_id = me and status = 'pending' order by created_at desc limit 1;
  if found then return to_jsonb(existing); end if;
  if (select count(*) from public.subscriptions where payer_id = me and created_at > now() - interval '1 day') >= 5 then
    raise exception 'too_many_orders' using errcode = 'P0001';
  end if;
  loop
    code := 'VG' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.subscriptions where order_code = code);
  end loop;
  insert into public.subscriptions (payer_id, plan_id, plan_name, price_vnd, days, order_code)
  values (me, pl.id, pl.name, pl.price_vnd, pl.days, code) returning * into s;
  return to_jsonb(s);
end $fn$;

-- Người mua huỷ đơn của mình khi còn chờ.
create or replace function public.cancel_my_pending_subscription() returns void
language sql security definer set search_path = '' as $fn$
  update public.subscriptions set status = 'cancelled' where payer_id = auth.uid() and status = 'pending';
$fn$;

-- Gói của một người dùng: tự mình mua, hoặc người chăm sóc đang liên kết mua. Chỉ máy chủ và hàm trong DB gọi.
create or replace function public.has_live_plan(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $fn$
  select exists (
    select 1 from public.subscriptions s
    where s.status = 'active' and s.expires_at > now()
      and (s.payer_id = p_user
           or s.payer_id in (select carer_id from public.family_links where owner_id = p_user and status = 'active'))
  );
$fn$;
revoke all on function public.has_live_plan(uuid) from public, anon, authenticated;
grant execute on function public.has_live_plan(uuid) to service_role;

-- Toàn cảnh cho app trong một lần gọi: các gói đang bán, hướng dẫn thanh toán, đơn mới nhất của mình, và mình có được hưởng không.
create or replace function public.plan_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare
  me uuid := auth.uid();
  mine public.subscriptions;
  covered_by text;
  live boolean;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select * into mine from public.subscriptions where payer_id = me
    order by (status = 'active' and expires_at > now()) desc, (status = 'pending') desc, created_at desc limit 1;
  select coalesce(p.display_name, p.username) into covered_by
    from public.subscriptions s
    join public.family_links l on l.carer_id = s.payer_id and l.owner_id = me and l.status = 'active'
    join public.profiles p on p.id = s.payer_id
   where s.status = 'active' and s.expires_at > now() and s.payer_id <> me
   order by s.expires_at desc limit 1;
  live := public.has_live_plan(me);
  return jsonb_build_object(
    'plans', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'price_vnd', price_vnd, 'days', days, 'note', note) order by sort, price_vnd)
                        from public.plans where active and price_vnd > 0), '[]'::jsonb),
    'pay_note', (select pay_note from public.plan_settings where id = 1),
    'mine', case when mine.id is null then null else to_jsonb(mine) - 'payer_id' - 'plan_id' - 'admin_note' end,
    'covered_by', covered_by,
    'live', live
  );
end $fn$;

revoke execute on function public.request_subscription(uuid) from anon, public;
revoke execute on function public.cancel_my_pending_subscription() from anon, public;
revoke execute on function public.plan_overview() from anon, public;
grant execute on function public.request_subscription(uuid) to authenticated;
grant execute on function public.cancel_my_pending_subscription() to authenticated;
grant execute on function public.plan_overview() to authenticated;

-- Gói quá hạn chuyển sang expired (mỗi ngày).
select cron.schedule('expire-subscriptions', '5 0 * * *', $cron$update public.subscriptions set status = 'expired' where status = 'active' and expires_at <= now()$cron$);
