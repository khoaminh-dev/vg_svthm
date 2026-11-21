-- Số điện thoại cá nhân (để Vy gọi "con trai", "mẹ"...). Bảng RIÊNG, không để trong `profiles`:
-- chính sách `profiles read` cho mọi tài khoản đăng nhập đọc, nên số điện thoại ở đó sẽ lộ cho người lạ.
--
-- Quyền:
--   đọc : chính chủ, và người thân ĐANG liên kết hoạt động với chủ số (cả hai chiều: cha mẹ <-> con)
--   ghi : chỉ chính chủ
--   anon: không có quyền gì
create table if not exists public.profile_phones (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  phone      text not null check (phone ~ '^\+?[0-9]{8,15}$'),
  updated_at timestamptz not null default now()
);

alter table public.profile_phones enable row level security;

revoke all on public.profile_phones from anon;
grant select, insert, update, delete on public.profile_phones to authenticated;

drop policy if exists phones_select on public.profile_phones;
create policy phones_select on public.profile_phones
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.family_links l
      where l.status = 'active'
        and (
          (l.owner_id = auth.uid() and l.carer_id = profile_phones.user_id)
          or (l.carer_id = auth.uid() and l.owner_id = profile_phones.user_id)
        )
    )
  );

drop policy if exists phones_insert on public.profile_phones;
create policy phones_insert on public.profile_phones
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists phones_update on public.profile_phones;
create policy phones_update on public.profile_phones
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists phones_delete on public.profile_phones;
create policy phones_delete on public.profile_phones
  for delete to authenticated
  using (user_id = auth.uid());

-- Giữ `updated_at` đúng khi sửa số.
create or replace function public.profile_phones_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profile_phones_touch on public.profile_phones;
create trigger profile_phones_touch
  before update on public.profile_phones
  for each row execute function public.profile_phones_touch();
