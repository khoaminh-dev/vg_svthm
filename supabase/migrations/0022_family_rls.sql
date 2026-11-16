-- Mở quyền đọc dữ liệu sức khoẻ cho người chăm sóc đã liên kết (theo quyền từng người), và ghi hộ có điều kiện.
-- Không mở: messages, room_members, voice_*, ocr_records, health_feedback, push_prefs, device_tokens.

-- Ai đã ghi số đo (null = chính chủ).
alter table public.bp_readings add column if not exists recorded_by uuid references auth.users(id) on delete set null;

drop policy if exists "bp_select_family" on public.bp_readings;
create policy "bp_select_family" on public.bp_readings for select to authenticated
  using (user_id <> auth.uid() and public.can_view(user_id, 'health'));

drop policy if exists "bp_insert_family" on public.bp_readings;
create policy "bp_insert_family" on public.bp_readings for insert to authenticated
  with check (user_id <> auth.uid() and recorded_by = auth.uid() and public.can_edit(user_id, 'record_bp'));

drop policy if exists "ha_select_family" on public.health_assessments;
create policy "ha_select_family" on public.health_assessments for select to authenticated
  using (user_id <> auth.uid() and public.can_view(user_id, 'health'));

drop policy if exists "hp_select_family" on public.health_profile;
create policy "hp_select_family" on public.health_profile for select to authenticated
  using (user_id <> auth.uid() and public.can_view(user_id, 'health'));

drop policy if exists "hp_update_family" on public.health_profile;
create policy "hp_update_family" on public.health_profile for update to authenticated
  using (user_id <> auth.uid() and public.can_edit(user_id, 'profile_edit'))
  with check (user_id <> auth.uid() and public.can_edit(user_id, 'profile_edit'));

drop policy if exists "hq_select_family" on public.health_qa;
create policy "hq_select_family" on public.health_qa for select to authenticated
  using (user_id <> auth.uid() and public.can_view(user_id, 'vy_history'));

-- Tên và ảnh của người thân đã đọc được qua my_family(); không mở thêm chính sách trên profiles.
