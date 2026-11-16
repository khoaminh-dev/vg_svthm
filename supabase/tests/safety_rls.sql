-- Kiểm thử giai đoạn 4: lưới an toàn thuốc, SOS, thẻ y tế khẩn cấp.
-- Chạy: supabase db query --linked --project-ref <ref> -f supabase/tests/safety_rls.sql
-- Kết quả đúng là báo lỗi có chữ TEST_PASSED (cố ý, để dữ liệu thử bị huỷ).
do $$
declare
  a uuid := '00000000-0000-4000-8000-00000000e001'; -- cha mẹ
  b uuid := '00000000-0000-4000-8000-00000000e002'; -- con có alerts
  c uuid := '00000000-0000-4000-8000-00000000e003'; -- người lạ
  d uuid := '00000000-0000-4000-8000-00000000e004'; -- con thứ hai, KHÔNG có alerts
  lk uuid; s1 uuid; s2 uuid; n int; st text; r text; e0 uuid; e1 uuid; e2 uuid; e3 uuid; esc int; blood text; ph jsonb;
begin
  insert into auth.users (id, email, aud, role) values
    (a, 'e001@test.invalid', 'authenticated', 'authenticated'),
    (b, 'e002@test.invalid', 'authenticated', 'authenticated'),
    (c, 'e003@test.invalid', 'authenticated', 'authenticated'),
    (d, 'e004@test.invalid', 'authenticated', 'authenticated');
  insert into public.profiles (id, username, display_name) values (a, 'e_parent', 'Cha mẹ'), (b, 'e_child', 'Con'), (c, 'e_other', 'Lạ'), (d, 'e_child2', 'Con hai')
    on conflict (id) do nothing;
  insert into public.family_links (owner_id, carer_id) values (a, b) returning id into lk;
  insert into public.family_links (owner_id, carer_id, perms) values (a, d, '{"health": true, "alerts": false, "profile_edit": false}'::jsonb);

  -- ===== Lưới an toàn thuốc: mốc 15 và 45 phút =====
  insert into public.dose_events (owner_id, slot_label, due_date, due_at, window_end) values
    (a, 'Mới', current_date, now() - interval '5 minutes',  now() + interval '115 minutes') returning id into e0;
  insert into public.dose_events (owner_id, slot_label, due_date, due_at, window_end) values
    (a, 'Mười tám', current_date, now() - interval '18 minutes', now() + interval '102 minutes') returning id into e1;
  insert into public.dose_events (owner_id, slot_label, due_date, due_at, window_end) values
    (a, 'Năm mươi', current_date, now() - interval '50 minutes', now() + interval '70 minutes') returning id into e2;
  insert into public.dose_events (owner_id, slot_label, due_date, due_at, window_end, snoozed_until) values
    (a, 'Hoãn', current_date, now() - interval '50 minutes', now() + interval '70 minutes', now() + interval '10 minutes') returning id into e3;
  perform public.meds_escalate();
  select escalation into esc from public.dose_events where id = e0; assert esc = 0, 'chưa tới 15 phút thì chưa nhắc';
  select escalation into esc from public.dose_events where id = e1; assert esc = 1, 'quá 15 phút: nhắc cha mẹ';
  select escalation into esc from public.dose_events where id = e2; assert esc = 2, 'quá 45 phút: báo con';
  select escalation into esc from public.dose_events where id = e3; assert esc = 0, 'đang hoãn thì không nhắc';
  perform public.meds_escalate();
  select escalation into esc from public.dose_events where id = e2; assert esc = 2, 'chạy lại không đổi (chỉ báo một lần)';
  -- đã uống thì không bị nhắc
  update public.dose_events set status = 'taken', escalation = 0 where id = e1;
  update public.dose_events set due_at = now() - interval '20 minutes' where id = e1;
  perform public.meds_escalate();
  select escalation into esc from public.dose_events where id = e1; assert esc = 0, 'đã uống không bị nhắc';

  -- ===== SOS =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  s1 := public.trigger_sos(null, null);
  assert s1 is not null, 'SOS trả về id';
  s2 := public.trigger_sos(null, null);
  assert s2 = s1, 'bấm lại trong 2 phút không tạo SOS mới';
  select count(*) into n from public.sos_events where owner_id = a; assert n = 1, 'chỉ một SOS mở';

  -- người lạ và con không có alerts không thấy
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from public.sos_events; assert n = 0, 'người lạ không thấy SOS';
  begin perform public.ack_sos(s1); assert false, 'người lạ không được nhận SOS'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', d, 'role', 'authenticated')::text, true);
  select count(*) into n from public.sos_events; assert n = 0, 'con không có alerts không thấy SOS';
  begin perform public.ack_sos(s1); assert false, 'con không có alerts không được nhận'; exception when insufficient_privilege then null; end;

  -- con có alerts thấy và nhận; lần hai báo đã có người nhận
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.sos_events; assert n = 1, 'con có alerts thấy SOS';
  r := public.ack_sos(s1); assert r = 'ok', 'nhận SOS lần đầu';
  r := public.ack_sos(s1); assert r = 'already', 'nhận lần hai: đã có người nhận';
  select status into st from public.sos_events where id = s1; assert st = 'handled', 'đã xử lý';

  -- chủ không tự "nhận" SOS của mình; huỷ SOS đã xử lý thì báo already
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  begin perform public.ack_sos(s1); assert false, 'chủ không dùng ack'; exception when insufficient_privilege then null; end;
  assert public.cancel_sos(s1) = 'already', 'đã có người nhận thì huỷ trả already';
  -- sau 2 phút (giả lập) bấm lại tạo SOS mới, rồi huỷ được
  execute 'reset role';
  update public.sos_events set created_at = now() - interval '5 minutes' where id = s1;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  s2 := public.trigger_sos(null, null); assert s2 <> s1, 'SOS mới sau khi cái cũ đã xử lý';
  assert public.cancel_sos(s2) = 'ok', 'chủ huỷ SOS bấm nhầm';
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin perform public.cancel_sos(s2); assert false, 'con không được huỷ SOS của cha mẹ'; exception when insufficient_privilege then null; end;

  -- ===== Thẻ y tế khẩn cấp =====
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform public.save_emergency_card(a, '{"blood_type": "O+", "allergies": "Penicillin", "own_phone": "0912 345 678",
    "contacts": [{"name": "Minh", "phone": "0988 111 222"}, {"name": "Bỏ", "phone": ""}, {"name": "Lan", "phone": "+84 90 1234567"}]}');
  select blood_type, contacts into blood, ph from public.emergency_cards where owner_id = a;
  assert blood = 'O+', 'lưu nhóm máu'; assert jsonb_array_length(ph) = 2, 'bỏ liên hệ không có số';
  begin perform public.save_emergency_card(a, '{"blood_type": "Z+"}'); assert false, 'nhóm máu sai'; exception when invalid_parameter_value then null; end;
  begin perform public.save_emergency_card(a, '{"own_phone": "abc; drop"}'); assert false, 'số điện thoại sai'; exception when invalid_parameter_value then null; end;

  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.emergency_cards; assert n = 1, 'con có alerts xem được thẻ';
  begin perform public.save_emergency_card(a, '{"blood_type": "A+"}'); assert false, 'con không có profile_edit không được sửa'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', d, 'role', 'authenticated')::text, true);
  select count(*) into n from public.emergency_cards; assert n = 1, 'con có health xem được thẻ';
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from public.emergency_cards; assert n = 0, 'người lạ không thấy thẻ';
  begin perform public.save_emergency_card(a, '{"blood_type": "A+"}'); assert false, 'người lạ không được sửa'; exception when insufficient_privilege then null; end;

  -- con có profile_edit sửa hộ thì ghi nhật ký
  execute 'reset role';
  update public.family_links set perms = jsonb_set(perms, '{profile_edit}', 'true') where id = lk;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.save_emergency_card(a, '{"blood_type": "A+"}');
  execute 'reset role';
  select count(*) into n from public.family_audit where owner_id = a and action = 'edit_emergency_card'; assert n = 1, 'sửa hộ được ghi nhật ký';

  -- Tóm tắt không lỗi khi chạy (chưa tới giờ thì không gửi)
  perform public.family_daily();

  raise exception 'TEST_PASSED';
end $$;
