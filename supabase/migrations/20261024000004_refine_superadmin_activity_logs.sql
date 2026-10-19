-- Refine seed data for activity logs with actor UID and team metadata

delete from public.activity_logs;

insert into public.activity_logs (
    actor_username, actor_role, actor_display_name, action_type, action_title, description, target_id, metadata, created_at
) values
(
    'superadmin1', 'SuperAdmin', 'SuperAdmin1',
    'ROLE_CHANGE_APPROVE', 'เปลี่ยนบทบาทผู้ใช้',
    'อนุมัติการเปลี่ยนบทบาทผู้ใช้ UID u_1020304050 เป็น Admin',
    'u_1020304050', '{"role": "Admin", "status": "active"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '1 hour'
),
(
    'admin01', 'Admin', 'สมชาย แอดมิน',
    'TICKET_ASSIGN', 'มอบหมายงานซ่อม',
    'มอบหมายงานซ่อม Ticket #6262313107 ให้กับทีม techteam',
    '6262313107', '{"uid": "u_admin01", "team": "techteam", "building": "อาคารเรียนรวม"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '45 minutes'
),
(
    'tech01', 'Technician', 'ทีมช่าง techteam',
    'TECH_SUBMIT', 'ส่งงานช่าง',
    'ส่งรายงานผลการซ่อม Ticket #6262313107 อุปกรณ์จำนวน 2 ชิ้น',
    '6262313107', '{"uid": "u_tech01", "team": "techteam", "device_count": 2}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '30 minutes'
),
(
    'admin01', 'Admin', 'สมชาย แอดมิน',
    'REPORT_APPROVE', 'อนุมัติงานช่าง',
    'อนุมัติรายงานผลการซ่อม Ticket #6262313107 เรียบร้อยแล้ว',
    '6262313107', '{"uid": "u_admin01", "team": "techteam", "result": "approved"}'::jsonb,
    pg_catalog.timezone('Asia/Bangkok'::text, pg_catalog.now()) - interval '15 minutes'
);

select pg_catalog.pg_notify('pgrst', 'reload schema');

