CREATE OR REPLACE FUNCTION public.sync_tickets_on_technician_schedule_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_ticket RECORD;
    v_now TIMESTAMPTZ := pg_catalog.now();
    v_next_start TIMESTAMPTZ;
    v_next_end TIMESTAMPTZ;
    v_found_future BOOLEAN;
    v_idx INTEGER;
    v_candidate_start TIMESTAMPTZ;
    v_candidate_end TIMESTAMPTZ;
BEGIN
    -- ทำงานเฉพาะกรณีที่มีการเปลี่ยนแปลง start_time, end_time, หรือ status ของช่าง
    IF (TG_OP = 'UPDATE' AND 
        (OLD.start_time IS DISTINCT FROM NEW.start_time OR 
         OLD.end_time IS DISTINCT FROM NEW.end_time OR 
         OLD.status IS DISTINCT FROM NEW.status)) THEN

        -- ค้นหาช่วงเวลาในอนาคตที่ใกล้ที่สุดจากช่วงเวลาใหม่ของช่าง
        v_found_future := FALSE;
        v_next_start := NULL;
        v_next_end := NULL;

        IF NEW.status = true AND NEW.start_time IS NOT NULL AND NEW.end_time IS NOT NULL AND pg_catalog.cardinality(NEW.start_time) > 0 THEN
            FOR v_idx IN 1 .. pg_catalog.array_length(NEW.start_time, 1) LOOP
                v_candidate_start := (NEW.start_time[v_idx])::timestamptz;
                v_candidate_end := (NEW.end_time[v_idx])::timestamptz;

                -- เช็คว่ายังไม่หมดวัน (นับเต็มวันปฏิทิน)
                IF (v_candidate_end + interval '1 day') > v_now THEN
                    IF v_next_start IS NULL OR v_candidate_start < v_next_start THEN
                        v_next_start := v_candidate_start;
                        v_next_end := v_candidate_end;
                        v_found_future := TRUE;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- วนลูปอัปเดตทุก Ticket ที่มีสถานะ pending และเป็นของทีมช่างนี้
        FOR v_ticket IN
            SELECT "TicketId", next_fix_date_start, next_fix_date_end
            FROM public."FixList"
            WHERE status = 'pending'
              AND pg_catalog.lower(pg_catalog.btrim(technician_team)) = pg_catalog.lower(pg_catalog.btrim(NEW."teamName"))
            FOR UPDATE
        LOOP
            IF v_found_future THEN
                -- กรณีที่ 1: ช่างยังมีช่วงเวลาในอนาคต -> อัปเดตช่วงวันซ่อมตามช่วงเวลาใหม่
                UPDATE public."FixList"
                SET next_fix_date_start = v_next_start,
                    next_fix_date_end = v_next_end
                WHERE "TicketId" = v_ticket."TicketId";

                -- อัปเดตตารางอุปกรณ์ของ Ticket นั้นด้วย
                IF pg_catalog.to_regclass(pg_catalog.format('public.%I', v_ticket."TicketId")) IS NOT NULL THEN
                    EXECUTE pg_catalog.format(
                        'UPDATE public.%I SET next_fix_date = $1 WHERE status = %L AND deviceid IS NOT NULL',
                        v_ticket."TicketId", 'pending'
                    ) USING v_next_end;
                END IF;

                -- บันทึก Activity Log ว่ามีการปรับเปลี่ยนวันซ่อมตามช่าง
                PERFORM public.log_activity(
                    'system',
                    'System',
                    'TICKET_RESCHEDULE',
                    'ปรับช่วงเวลาซ่อมตามช่าง',
                    'คำร้อง Ticket #' || v_ticket."TicketId" || ' ได้รับการปรับช่วงเวลาเข้าซ่อมใหม่ตามตารางเวลาของทีม ' || NEW."teamName",
                    v_ticket."TicketId",
                    pg_catalog.jsonb_build_object(
                        'ticket_id', v_ticket."TicketId",
                        'team_name', NEW."teamName",
                        'new_start', v_next_start,
                        'new_end', v_next_end
                    ),
                    'ระบบอัตโนมัติ'
                );
            ELSE
                -- กรณีที่ 2: ช่างไม่มีช่วงเวลาในอนาคตเหลืออยู่เลย หรือถูกปิดการใช้งาน -> คืนสถานะเป็น validating
                UPDATE public."FixList"
                SET status = 'validating',
                    technician_team = NULL,
                    next_fix_date_start = NULL,
                    next_fix_date_end = NULL
                WHERE "TicketId" = v_ticket."TicketId";

                IF pg_catalog.to_regclass(pg_catalog.format('public.%I', v_ticket."TicketId")) IS NOT NULL THEN
                    EXECUTE pg_catalog.format(
                        'UPDATE public.%I SET status = %L, next_fix_date = NULL WHERE status IN (%L, %L) AND deviceid IS NOT NULL',
                        v_ticket."TicketId", 'validating', 'pending', 'validating'
                    );
                END IF;

                PERFORM public.sync_maintenance_team_ticket_assignment(
                    v_ticket."TicketId",
                    NEW."teamName",
                    NULL,
                    false
                );

                PERFORM public.log_activity(
                    'system',
                    'System',
                    'TICKET_AUTO_REVERT',
                    'หมดช่วงเวลาปฏิบัติงานช่าง',
                    'คำร้อง Ticket #' || v_ticket."TicketId" || ' ถูกคืนสถานะเป็น validating เนื่องจากทีม ' || NEW."teamName" || ' ไม่มีช่วงเวลาเข้าซ่อมในอนาคต',
                    v_ticket."TicketId",
                    pg_catalog.jsonb_build_object(
                        'ticket_id', v_ticket."TicketId",
                        'team_name', NEW."teamName",
                        'reason', 'technician_schedule_removed'
                    ),
                    'ระบบอัตโนมัติ'
                );
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

-- สร้าง Trigger ผูกกับตาราง Maintenance_Users
DROP TRIGGER IF EXISTS trg_sync_tickets_on_technician_schedule_update ON public."Maintenance_Users";
CREATE TRIGGER trg_sync_tickets_on_technician_schedule_update
AFTER UPDATE OF start_time, end_time, status ON public."Maintenance_Users"
FOR EACH ROW
EXECUTE FUNCTION public.sync_tickets_on_technician_schedule_update();

