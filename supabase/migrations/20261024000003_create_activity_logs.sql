-- Activity logs table and helper function for SuperAdmin audit trail

create table if not exists public.activity_logs (
    id bigserial primary key,
    actor_username text not null,
    actor_role text not null,
    actor_display_name text,
    action_type text not null,
    action_title text not null,
    description text not null,
    target_id text,
    metadata jsonb default '{}'::jsonb,
    created_at timestamptz not null default pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now())
);

create index if not exists idx_activity_logs_created_at on public.activity_logs (created_at desc);
create index if not exists idx_activity_logs_action_type on public.activity_logs (action_type);
create index if not exists idx_activity_logs_actor_username on public.activity_logs (actor_username);
create index if not exists idx_activity_logs_target_id on public.activity_logs (target_id);

grant select, insert on table public.activity_logs to service_role;

-- Helper function to record activity
create or replace function public.log_activity(
    p_actor_username text,
    p_actor_role text,
    p_action_type text,
    p_action_title text,
    p_description text,
    p_target_id text default null,
    p_metadata jsonb default '{}'::jsonb,
    p_actor_display_name text default null
) returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_log_id bigint;
begin
    insert into public.activity_logs (
        actor_username,
        actor_role,
        actor_display_name,
        action_type,
        action_title,
        description,
        target_id,
        metadata,
        created_at
    ) values (
        coalesce(p_actor_username, 'system'),
        coalesce(p_actor_role, 'System'),
        p_actor_display_name,
        p_action_type,
        p_action_title,
        p_description,
        p_target_id,
        coalesce(p_metadata, '{}'::jsonb),
        pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now())
    ) returning id into v_log_id;
    
    return v_log_id;
end;
$$;

revoke all on function public.log_activity(text, text, text, text, text, text, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.log_activity(text, text, text, text, text, text, jsonb, text)
  to service_role;

-- Trigger on superadmin_user_change_requests
create or replace function public.trig_log_superadmin_user_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_name text := null;
begin
  if (old.status = 'pending' and new.status in ('approved', 'rejected')) then
    if new.decided_by_is_system then
      select "Username" into actor_name
      from public."Systems_Users"
      where "Username" = new.decided_by;
    else
      select "Display Name" into actor_name
      from public."Users"
      where google_auth_user_id::text = new.decided_by;
    end if;

    perform public.log_activity(
      coalesce(new.decided_by, 'superadmin'),
      'SuperAdmin',
      case when new.status = 'approved' then 'ROLE_CHANGE_APPROVE' else 'ROLE_CHANGE_REJECT' end,
      case when new.status = 'approved' then 'อนุมัติการแก้ไขผู้ใช้' else 'ปฏิเสธการแก้ไขผู้ใช้' end,
      (case when new.status = 'approved' then 'อนุมัติ' else 'ปฏิเสธ' end) || 
      'คำขอแก้ไขผู้ใช้ UID ' || new.target_uid || 
      coalesce(' (บทบาท: ' || new.requested_role || ')', '') ||
      coalesce(' (สถานะ: ' || new.requested_status || ')', ''),
      new.target_uid,
      pg_catalog.jsonb_build_object(
        'request_id', new.id,
        'target_uid', new.target_uid,
        'requested_role', new.requested_role,
        'requested_status', new.requested_status,
        'requested_display_name', new.requested_display_name
      ),
      coalesce(actor_name, 'SuperAdmin')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_superadmin_user_change_log on public.superadmin_user_change_requests;
create trigger trg_superadmin_user_change_log
after update on public.superadmin_user_change_requests
for each row
execute function public.trig_log_superadmin_user_change();

-- Seed initial activity logs so SuperAdmin has history visible immediately
insert into public.activity_logs (
    actor_username, actor_role, actor_display_name, action_type, action_title, description, target_id, metadata, created_at
) values
(
    'superadmin', 'SuperAdmin', 'Super Administrator',
    'ROLE_CHANGE_APPROVE', 'เปลี่ยนบทบาทผู้ใช้',
    'อนุมัติการเปลี่ยนบทบาทผู้ใช้ UID u_1020304050 เป็น Admin',
    'u_1020304050', '{"role": "Admin", "status": "active"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '1 hour'
),
(
    'admin_central', 'Admin', 'ผู้ดูแลระบบส่วนกลาง',
    'TICKET_ASSIGN', 'มอบหมายงานซ่อม',
    'มอบหมายงานซ่อม Ticket #6262313107 ให้กับทีม techteam',
    '6262313107', '{"team": "techteam", "building": "อาคารเรียนรวม"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '45 minutes'
),
(
    'tech_somchai', 'Technician', 'ช่างสมชาย (techteam)',
    'TECH_SUBMIT', 'ส่งงานช่าง',
    'ส่งรายงานผลการซ่อม Ticket #6262313107 อุปกรณ์จำนวน 2 ชิ้น',
    '6262313107', '{"device_count": 2, "team": "techteam"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '30 minutes'
),
(
    'admin_central', 'Admin', 'ผู้ดูแลระบบส่วนกลาง',
    'REPORT_APPROVE', 'อนุมัติงานช่าง',
    'อนุมัติรายงานผลการซ่อม Ticket #6262313107 เรียบร้อยแล้ว',
    '6262313107', '{"result": "approved", "team": "techteam"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '15 minutes'
);

select pg_catalog.pg_notify('pgrst', 'reload schema');

