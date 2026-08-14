create type public.report_status as enum ('uploading','submitted','issue_created','agent_ready','agent_running','pr_opened','completed','needs_info','agent_failed','rejected','upload_failed');
create type public.agent_run_status as enum ('claimed','running','completed','needs_info','failed','timed_out');

create table public.reports (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 idempotency_key uuid not null unique, status public.report_status not null default 'uploading', reporter_name text,
 category text not null check (category in ('bug','usability','request','other')), comment text not null check (length(comment) between 1 and 4000), expected text,
 app_version text not null, build_sha text, environment jsonb not null, artifacts jsonb not null default '[]',
 raw_screenshot_path text, raw_log_path text, redacted_screenshot_path text, redacted_log_path text,
 redaction_status text not null default 'pending' check (redaction_status in ('pending','approved','review_required')),
 redaction_version text not null default 'rules-v1', consented_at timestamptz not null, github_issue_number bigint unique, github_issue_url text,
 expires_at timestamptz default now() + interval '30 days', constraint report_paths_scoped check (
  (raw_screenshot_path is null or raw_screenshot_path like 'reports/' || id || '/raw/%') and
  (raw_log_path is null or raw_log_path like 'reports/' || id || '/raw/%') and
  (redacted_screenshot_path is null or redacted_screenshot_path like 'reports/' || id || '/redacted/%') and
  (redacted_log_path is null or redacted_log_path like 'reports/' || id || '/redacted/%'))
);
create table public.agent_runs (
 id uuid primary key default gen_random_uuid(), report_id uuid not null references public.reports(id), github_issue_number bigint not null,
 agent text not null check (agent in ('codex','claude')), status public.agent_run_status not null default 'claimed', claimed_at timestamptz not null default now(),
 started_at timestamptz, finished_at timestamptz, branch_name text, github_pr_number bigint, result_summary jsonb,
 intervention_count integer not null default 0, failure_code text
);
create unique index one_active_run_per_report on public.agent_runs(report_id) where status in ('claimed','running');
create table public.report_events (
 id bigint generated always as identity primary key, report_id uuid not null references public.reports(id), agent_run_id uuid references public.agent_runs(id),
 occurred_at timestamptz not null default now(), event_type text not null, actor text not null, details jsonb not null default '{}'
);
create table public.report_rate_limits (client_key text primary key, window_start timestamptz not null, attempts integer not null);
alter table public.reports enable row level security;
alter table public.agent_runs enable row level security;
alter table public.report_events enable row level security;
alter table public.report_rate_limits enable row level security;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values ('user-reports','user-reports',false,10485760,array['image/png','application/x-ndjson','application/json'])
 on conflict (id) do update set public=false;
-- Intentionally no anon/authenticated policies. All access is mediated by Edge functions.

create or replace function public.claim_agent_run(p_report_id uuid, p_issue bigint, p_agent text)
returns public.agent_runs language plpgsql security definer set search_path = public as $$
declare claimed public.agent_runs;
begin
 if p_agent not in ('codex','claude') then raise exception 'unsupported agent'; end if;
 update reports set status='agent_running',updated_at=now() where id=p_report_id and github_issue_number=p_issue and status in ('issue_created','agent_ready','agent_failed','needs_info');
 if not found then return null; end if;
 insert into agent_runs(report_id,github_issue_number,agent) values(p_report_id,p_issue,p_agent) returning * into claimed;
 insert into report_events(report_id,agent_run_id,event_type,actor) values(p_report_id,claimed.id,'run_claimed','dispatcher');
 return claimed;
end $$;
revoke all on function public.claim_agent_run(uuid,bigint,text) from public, anon, authenticated;
grant execute on function public.claim_agent_run(uuid,bigint,text) to service_role;

create or replace function public.consume_report_rate_limit(p_client_key text, p_limit integer default 10)
returns boolean language plpgsql security definer set search_path=public as $$
declare allowed boolean;
begin
 insert into report_rate_limits(client_key,window_start,attempts) values(p_client_key,date_trunc('hour',now()),1)
 on conflict(client_key) do update set window_start=case when report_rate_limits.window_start < now()-interval '1 hour' then date_trunc('hour',now()) else report_rate_limits.window_start end,
 attempts=case when report_rate_limits.window_start < now()-interval '1 hour' then 1 else report_rate_limits.attempts+1 end
 returning attempts <= p_limit into allowed;
 return allowed;
end $$;
revoke all on function public.consume_report_rate_limit(text,integer) from public,anon,authenticated;
grant execute on function public.consume_report_rate_limit(text,integer) to service_role;

create or replace function public.recover_stale_agent_runs(p_before timestamptz)
returns integer language plpgsql security definer set search_path=public as $$
declare recovered integer;
begin
 with stale as (update agent_runs set status='timed_out',finished_at=now(),failure_code='stale_claim' where status in ('claimed','running') and claimed_at<p_before returning id,report_id),
 reports_updated as (update reports r set status='agent_failed',updated_at=now() from stale s where r.id=s.report_id returning r.id)
 insert into report_events(report_id,agent_run_id,event_type,actor,details) select report_id,id,'run_timed_out','dispatcher_recovery','{"failureCode":"stale_claim"}'::jsonb from stale;
 get diagnostics recovered = row_count; return recovered;
end $$;
revoke all on function public.recover_stale_agent_runs(timestamptz) from public,anon,authenticated;
grant execute on function public.recover_stale_agent_runs(timestamptz) to service_role;
