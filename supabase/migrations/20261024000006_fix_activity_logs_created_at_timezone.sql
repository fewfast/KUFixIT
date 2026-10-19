ALTER TABLE public.activity_logs 
ALTER COLUMN created_at SET DEFAULT now();

-- ปรับแก้ฟังก์ชัน log_activity ไม่ให้ครอบ timezone()
CREATE OR REPLACE FUNCTION public.log_activity(
    p_actor_username TEXT,
    p_actor_role TEXT,
    p_action_type TEXT,
    p_action_title TEXT,
    p_description TEXT,
    p_target_id TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_actor_display_name TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_log_id BIGINT;
BEGIN
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
    ) VALUES (
        COALESCE(p_actor_username, 'system'),
        COALESCE(p_actor_role, 'System'),
        p_actor_display_name,
        p_action_type,
        p_action_title,
        p_description,
        p_target_id,
        COALESCE(p_metadata, '{}'::jsonb),
        now()
    ) RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$;

SELECT pg_catalog.pg_notify('pgrst', 'reload schema');

