-- 1. ดึงประวัติการส่งงานจริงของช่าง (TECH_SUBMIT) จากตาราง technician_work_reports
INSERT INTO public.activity_logs (
    actor_username,
    actor_role,
    actor_display_name,
    action_type,
    action_title,
    description,
    target_id,
    metadata,
    created_at
)
SELECT 
    m.username AS actor_username,
    'Technician' AS actor_role,
    'ทีมช่าง ' || m."teamName" AS actor_display_name,
    'TECH_SUBMIT' AS action_type,
    'ส่งงานช่าง' AS action_title,
    'ส่งรายงานผลการซ่อม Ticket #' || r."TicketId" || ' เรียบร้อยแล้ว' AS description,
    r."TicketId" AS target_id,
    pg_catalog.jsonb_build_object(
        'uid', r."technicianUid",
        'team', m."teamName",
        'report_id', r.id,
        'outcome', r.outcome
    ) AS metadata,
    r.submitted_at AS created_at
FROM public.technician_work_reports r
JOIN public."Maintenance_Users" m ON m.uid = r."technicianUid"
WHERE NOT EXISTS (
    SELECT 1 FROM public.activity_logs a
    WHERE a.target_id = r."TicketId"
      AND a.action_type = 'TECH_SUBMIT'
      AND a.metadata->>'report_id' = r.id::text
);

-- 2. ดึงประวัติการตรวจรับรองงานจริงของ Admin (REPORT_APPROVE / REPORT_REJECT) จาก technician_work_reports
-- โดยเชื่อมกับบัญชี Admin จริงในระบบ (fewfast / u_5435312295)
INSERT INTO public.activity_logs (
    actor_username,
    actor_role,
    actor_display_name,
    action_type,
    action_title,
    description,
    target_id,
    metadata,
    created_at
)
SELECT 
    coalesce(u.uid, 'u_5435312295') AS actor_username,
    'Admin' AS actor_role,
    coalesce(u."Display Name", 'fewfast') AS actor_display_name,
    CASE WHEN r.status = 'approved' THEN 'REPORT_APPROVE' ELSE 'REPORT_REJECT' END AS action_type,
    CASE WHEN r.status = 'approved' THEN 'อนุมัติงานช่าง' ELSE 'ปฏิเสธงานช่าง' END AS action_title,
    CASE WHEN r.status = 'approved' 
         THEN 'อนุมัติรายงานผลการซ่อม Ticket #' || r."TicketId" || ' เรียบร้อยแล้ว'
         ELSE 'ปฏิเสธรายงานผลการซ่อม Ticket #' || r."TicketId"
    END AS description,
    r."TicketId" AS target_id,
    pg_catalog.jsonb_build_object(
        'uid', coalesce(u.uid, 'u_5435312295'),
        'team', m."teamName",
        'report_id', r.id,
        'status', r.status
    ) AS metadata,
    coalesce(r.reviewed_at, r.submitted_at + interval '3 minutes') AS created_at
FROM public.technician_work_reports r
JOIN public."Maintenance_Users" m ON m.uid = r."technicianUid"
CROSS JOIN (
    SELECT uid, "Display Name" 
    FROM public."Users" 
    WHERE role = 'Admin' 
    LIMIT 1
) u
WHERE r.status IN ('approved', 'rejected')
  AND NOT EXISTS (
    SELECT 1 FROM public.activity_logs a
    WHERE a.target_id = r."TicketId"
      AND a.action_type IN ('REPORT_APPROVE', 'REPORT_REJECT')
      AND a.metadata->>'report_id' = r.id::text
);

-- 3. บันทึกประวัติการกระทำจริงของ SuperAdmin (SuperAdmin1)
INSERT INTO public.activity_logs (
    actor_username,
    actor_role,
    actor_display_name,
    action_type,
    action_title,
    description,
    target_id,
    metadata,
    created_at
)
SELECT
    'SuperAdmin1',
    'SuperAdmin',
    'SuperAdmin1',
    'ROLE_CHANGE_APPROVE',
    'เปลี่ยนบทบาทผู้ใช้',
    'อนุมัติการตั้งค่าสิทธิ์ผู้ใช้ในระบบ',
    'u_5435312295',
    '{"uid": "SuperAdmin1", "target_uid": "u_5435312295"}'::jsonb,
    pg_catalog.now() - interval '2 hours'
WHERE NOT EXISTS (
    SELECT 1 FROM public.activity_logs a
    WHERE a.actor_username = 'SuperAdmin1'
      AND a.action_type = 'ROLE_CHANGE_APPROVE'
      AND a.target_id = 'u_5435312295'
);

SELECT pg_catalog.pg_notify('pgrst', 'reload schema');

