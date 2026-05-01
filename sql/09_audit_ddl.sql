-- ------------------------------------------------------------
-- File: 09_audit_ddl.sql
-- Purpose: Event trigger to audit DDL statements (CREATE, ALTER,
--          DROP, etc.) and store them in the audit_ddl_logs table.
-- ------------------------------------------------------------

-- Create a table to store DDL audit entries (if not already present)
DO $$
BEGIN
   IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relname = 'audit_ddl_logs'
        AND n.nspname = 'public'
   ) THEN
      CREATE TABLE public.audit_ddl_logs (
         id          BIGSERIAL PRIMARY KEY,
         command_tag TEXT      NOT NULL,   -- e.g., CREATE TABLE, ALTER TABLE
         object_type TEXT,                -- TABLE, INDEX, FUNCTION, etc.
         object_name TEXT,                -- fully‑qualified name
         command_sql TEXT,                -- DDL summary (tag + object identity); deparse-to-full-sql is version-dependent
         executed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
         user_name   TEXT NOT NULL DEFAULT session_user
      );
   END IF;
END
$$;

-- Event trigger function that captures DDL commands
CREATE OR REPLACE FUNCTION func_audit_ddl()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
   cmd record;
BEGIN
   -- pg_event_trigger_ddl_commands() returns one row for each DDL object affected;
   -- iterate and insert a log row for each one.
   FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
      INSERT INTO public.audit_ddl_logs (
         command_tag,
         object_type,
         object_name,
         command_sql,
         user_name
      ) VALUES (
         TG_TAG,
         cmd.object_type,
         cmd.object_identity,
         -- NOTE: pg_event_trigger_ddl_commands().command is type pg_ddl_command (internal).
         -- Deparsing to full textual SQL is version-dependent; we store a stable summary instead.
         cmd.command_tag || ' ' || COALESCE(cmd.object_identity, ''),
         session_user
      );
   END LOOP;
END;
$$
SET search_path = public, pg_temp;

-- Register the event trigger for all DDL commands
DROP EVENT TRIGGER IF EXISTS audit_ddl_trigger;
CREATE EVENT TRIGGER audit_ddl_trigger
   ON ddl_command_end
   EXECUTE FUNCTION func_audit_ddl();

-- Grant read access to auditor (mirrors the pattern in 08_grants.sql)
GRANT SELECT ON public.audit_ddl_logs TO auditor;

-- app_user must not read DDL audit logs
REVOKE ALL ON public.audit_ddl_logs FROM PUBLIC, app_user;
