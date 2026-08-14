-- Edge Functions use the service-role JWT through PostgREST. RLS bypass alone
-- does not grant SQL privileges, so grant only the operations each function uses.
revoke all on table public.reports from anon, authenticated;
revoke all on table public.agent_runs from anon, authenticated;
revoke all on table public.report_events from anon, authenticated;
revoke all on table public.report_rate_limits from anon, authenticated;

grant usage on schema public to service_role;
grant select, insert, update on table public.reports to service_role;
grant select, update on table public.agent_runs to service_role;
grant insert on table public.report_events to service_role;

-- report_events.id is an identity column. Keep the backing sequence private
-- while allowing service-role inserts on PostgreSQL versions that check it.
grant usage on sequence public.report_events_id_seq to service_role;
