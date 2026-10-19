CREATE OR REPLACE FUNCTION public.check_and_expire_overdue_tickets()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_ticket RECORD;
    v_tech RECORD;
    v_now TIMESTAMPTZ := pg_catalog.now();
    v_next_start TIMESTAMPTZ;
    v_next_end TIMESTAMPTZ;
    v_found_future BOOLEAN;
    v_idx INTEGER;
    v_candidate_start TIMESTAMPTZ;
    v_candidate_end TIMESTAMPTZ;
    v_rescheduled_count INTEGER := 0;
    v_reverted_count INTEGER := 0;
BEGIN
    -- วนลูปหาตั๋วที่สถานะเป็น pending และเลย next_fix_date_end ไปแล้ว
    FOR v_ticket IN
        SELECT "TicketId", technician_team, next_fix_date_start, next_fix_date_end
        FROM public."FixList"
        WHERE status = 'pending'
          AND next_fix_date_end IS NOT NULL
          AND next_fix_date_end < v_now
        FOR UPDATE
    LOOP
        v_found_future := FALSE;
        v_next_start := NULL;
        v_next_end := NULL;

        -- ค้นหาช่วงเวลาของทีมช่างจาก Maintenance_Users
        IF v_ticket.technician_team IS NOT NULL AND pg_catalog.btrim(v_ticket.technician_team) <> '' THEN
            SELECT uid, "teamName", start_time, end_time
            INTO v_tech
            FROM public."Maintenance_Users"
            WHERE "teamName" = v_ticket.technician_team
              AND status = true
            ORDER BY created_at ASC
            LIMIT 1;

            IF v_tech.uid IS NOT NULL AND v_tech.start_time IS NOT NULL AND v_tech.end_time IS NOT NULL THEN
                -- วนลูปหาช่วงเวลาถัดไปที่อยู่ในอนาคต (เรียงจากใกล้ไปไกล)
                FOR v_idx IN 1 .. pg_catalog.array_length(v_tech.start_time, 1) LOOP
                    v_candidate_start := (v_tech.start_time[v_idx])::timestamptz;
                    v_candidate_end := (v_tech.end_time[v_idx])::timestamptz;

                    -- ตรวจสอบว่าช่วงเวลาสิ้นสุดยังไม่เลยเวลาปัจจุบัน
                    IF v_candidate_end >= v_now THEN
                        IF v_next_start IS NULL OR v_candidate_start < v_next_start THEN
                            v_next_start := v_candidate_start;
                            v_next_end := v_candidate_end;
                            v_found_future := TRUE;
                        END IF;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        IF v_found_future THEN
            -- กรณีที่ 1: ช่างยังมีช่วงเวลาในอนาคต -> เลื่อนช่วงเวลาเข้าซ่อมเป็นช่วงถัดไป
            UPDATE public."FixList"
            SET next_fix_date_start = v_next_start,
                next_fix_date_end = v_next_end
            WHERE "TicketId" = v_ticket."TicketId";

            -- อัปเดตในตารางอุปกรณ์ด้วย
            IF pg_catalog.to_regclass(pg_catalog.format('public.%I', v_ticket."TicketId")) IS NOT NULL THEN
                EXECUTE pg_catalog.format(
                    'UPDATE public.%I SET next_fix_date = $1 WHERE status = %L AND deviceid IS NOT NULL',
                    v_ticket."TicketId", 'pending'
                ) USING v_next_end;
            END IF;

            v_rescheduled_count := v_rescheduled_count + 1;
        ELSE
            -- กรณีที่ 2: ไม่มีช่วงเวลาในอนาคต -> ถอดช่าง, คืนสถานะเป็น validating, เคลียร์วันเข้าซ่อม
            UPDATE public."FixList"
            SET status = 'validating',
                technician_team = NULL,
                next_fix_date_start = NULL,
                next_fix_date_end = NULL
            WHERE "TicketId" = v_ticket."TicketId";

            -- คืนสถานะอุปกรณ์ทุกชิ้นที่ pending/validating ให้กลับเป็น validating
            IF pg_catalog.to_regclass(pg_catalog.format('public.%I', v_ticket."TicketId")) IS NOT NULL THEN
                EXECUTE pg_catalog.format(
                    'UPDATE public.%I SET status = %L, next_fix_date = NULL WHERE status IN (%L, %L) AND deviceid IS NOT NULL',
                    v_ticket."TicketId", 'validating', 'pending', 'validating'
                );
            END IF;

            -- ถอดตั๋วออกจากตารางงานของช่างเดิม
            IF v_ticket.technician_team IS NOT NULL AND pg_catalog.btrim(v_ticket.technician_team) <> '' THEN
                PERFORM public.sync_maintenance_team_ticket_assignment(
                    v_ticket."TicketId",
                    v_ticket.technician_team,
                    NULL,
                    false
                );
            END IF;

            -- บันทึก Activity Log
            PERFORM public.log_activity(
                'system',
                'System',
                'TICKET_AUTO_REVERT',
                'หมดช่วงเวลาปฏิบัติงานช่าง',
                'คำร้อง Ticket #' || v_ticket."TicketId" || ' ถูกคืนสถานะเป็น validating เนื่องจากหมดช่วงเวลาเข้าซ่อมของทีม ' || coalesce(v_ticket.technician_team, '-'),
                v_ticket."TicketId",
                pg_catalog.jsonb_build_object(
                    'ticket_id', v_ticket."TicketId",
                    'previous_team', v_ticket.technician_team,
                    'reason', 'no_future_work_period'
                ),
                'ระบบอัตโนมัติ'
            );

            v_reverted_count := v_reverted_count + 1;
        END IF;
    END LOOP;

    RETURN pg_catalog.jsonb_build_object(
        'rescheduled_count', v_rescheduled_count,
        'reverted_count', v_reverted_count
    );
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_expire_overdue_tickets() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_expire_overdue_tickets() TO service_role;

SELECT pg_catalog.pg_notify('pgrst', 'reload schema');

