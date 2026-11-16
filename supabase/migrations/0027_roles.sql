-- Vai trò của tài khoản: người cao tuổi hoặc người thân. Quyết định bộ khung giao diện trong app.
-- App đọc vai trò từ metadata của phiên đăng nhập (đồng bộ, dùng được ngay trong chuyển hướng);
-- cột này là bản sao phía máy chủ để các chức năng thông báo và thống kê dùng.
alter table public.profiles add column if not exists role text check (role in ('elder', 'family'));

create or replace function public.set_my_role(p_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_role not in ('elder', 'family') then raise exception 'bad_role' using errcode = '22023'; end if;
  update public.profiles set role = p_role where id = auth.uid();
end $$;
revoke all on function public.set_my_role(text) from public, anon;
grant execute on function public.set_my_role(text) to authenticated;

-- Đồng bộ vai trò từ metadata đăng ký/cập nhật sang hồ sơ (người đăng ký chọn vai trò ngay từ form).
create or replace function public.sync_profile_role() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v text := new.raw_user_meta_data ->> 'role';
begin
  if v in ('elder', 'family') then
    update public.profiles set role = v where id = new.id and role is distinct from v;
  end if;
  return new;
end $$;
revoke all on function public.sync_profile_role() from public, anon, authenticated;
drop trigger if exists zz_sync_profile_role on auth.users;
create trigger zz_sync_profile_role after insert or update of raw_user_meta_data on auth.users
  for each row execute function public.sync_profile_role();
