-- Supabase stops granting new public tables to service_role on 2026-10-30.
grant select, insert, update, delete on all tables in schema public to service_role;
