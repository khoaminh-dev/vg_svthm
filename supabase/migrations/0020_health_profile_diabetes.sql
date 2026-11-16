-- Hồ sơ sức khoẻ: thêm các câu cho model nguy cơ tiểu đường (đều không bắt buộc, null = chưa khai).
alter table public.health_profile
  add column if not exists high_cholesterol boolean,
  add column if not exists difficulty_walking boolean,
  add column if not exists height_cm smallint check (height_cm is null or height_cm between 100 and 230),
  add column if not exists weight_kg smallint check (weight_kg is null or weight_kg between 25 and 250);
