create or replace function public.delete_maintenance_technician(p_technician_uid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  technician_username text;
  technician_team_name text;
  deleted_login_count integer;
  active_ticket_count integer := 0;
  pending_report_count integer := 0;
  technician_table regclass;
  technician_table_count integer := 0;
begin
  if p_technician_uid is null or p_technician_uid !~ '^t_[0-9]{10}$' then
    raise exception 'Invalid technician UID.';
  end if;

  -- ดึงข้อมูล username และ teamName ของช่าง
  select technician.username, technician."teamName"
  into technician_username, technician_team_name
  from public."Maintenance_Users" as technician
  where technician.uid = p_technician_uid
  for update;

  if not found then
    return false;
  end if;

  -- 1. ตรวจสอบตั๋วใน FixList ที่ยังเป็น pending หรือ validating
  select count(*)
  into active_ticket_count
  from public."FixList"
  where technician_team = technician_team_name
    and status in ('pending', 'validating');

  -- 2. ตรวจสอบตารางประจำตัวช่าง (public."t_XXXXXXXXXX")
  technician_table := pg_catalog.to_regclass(
    pg_catalog.format('public.%I', p_technician_uid)
  );
  if technician_table is not null then
    execute pg_catalog.format('select count(*) from %s', technician_table)
    into technician_table_count;
  end if;

  -- 3. ตรวจสอบรายงานที่รอตรวจรับรอง (under_review)
  select count(*)
  into pending_report_count
  from public.technician_work_reports
  where "technicianUid" = p_technician_uid
    and status = 'under_review';

  -- หากยังมีงานค้างอยู่ ให้โยน Exception ป้องกันการลบ
  if active_ticket_count > 0 or technician_table_count > 0 or pending_report_count > 0 then
    raise exception 'ACTIVE_JOBS_EXIST: ไม่สามารถลบทีมช่างได้ เนื่องจากยังมีงานซ่อมที่ค้างอยู่ (% รายการ) กรุณาย้ายงานหรือปิดงานให้เรียบร้อยก่อน', 
      (active_ticket_count + technician_table_count + pending_report_count);
  end if;

  -- ตรวจสอบบัญชีเข้าสู่ระบบใน Systems_Users
  perform 1
  from public."Systems_Users" as login_account
  where login_account.role = 'Technician'
    and pg_catalog.lower(pg_catalog.btrim(login_account."Username")) =
      pg_catalog.lower(pg_catalog.btrim(technician_username))
  for update;

  if not found then
    raise exception 'Technician login account could not be found.';
  end if;

  -- บันทึก UID เข้าตาราง Deleted_Maintenance_Technicians เพื่อป้องกันการใช้ซ้ำ
  insert into public."Deleted_Maintenance_Technicians" (uid)
  values (p_technician_uid)
  on conflict (uid) do nothing;

  -- ลบบัญชีจาก Systems_Users
  delete from public."Systems_Users" as login_account
  where login_account.role = 'Technician'
    and pg_catalog.lower(pg_catalog.btrim(login_account."Username")) =
      pg_catalog.lower(pg_catalog.btrim(technician_username));
  get diagnostics deleted_login_count = row_count;
  if deleted_login_count <> 1 then
    raise exception 'Technician login account could not be deleted.';
  end if;

  -- ลบจาก Maintenance_Users
  delete from public."Maintenance_Users" as technician
  where technician.uid = p_technician_uid;
  if not found then
    raise exception 'Technician profile could not be deleted.';
  end if;

  -- ลบตารางประจำตัวช่างทิ้งถ้ามี
  if technician_table is not null then
    execute pg_catalog.format('drop table if exists %s cascade', technician_table);
  end if;

  return true;
end;
$$;

revoke all on function public.delete_maintenance_technician(text)
  from public, anon, authenticated;
grant execute on function public.delete_maintenance_technician(text)
  to service_role;

do $$
begin
  perform pg_catalog.pg_notify('pgrst', 'reload schema');
end;
$$;

