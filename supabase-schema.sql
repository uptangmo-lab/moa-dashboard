-- Moa shared workspaces with category-scoped access.
-- Run this after the original moa_workspace_state table has been created.
create table if not exists public.moa_workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  workspace_name text not null default '내 워크스페이스',
  admin_email text not null default '',
  currency text not null default 'KRW' check (currency in ('KRW','THB','USD')),
  workspace_goal_krw numeric not null default 30000000,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.moa_workspaces add column if not exists workspace_goal_krw numeric not null default 30000000;

create table if not exists public.moa_team_members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.moa_workspaces(id) on delete cascade,
  email text not null,
  role text not null check (role in ('admin','subadmin','employee')),
  business_ids text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (workspace_id, email)
);

create table if not exists public.moa_business_records (
  workspace_id uuid not null references public.moa_workspaces(id) on delete cascade,
  business_id text not null,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, business_id)
);

create or replace function public.moa_is_workspace_admin(target_workspace uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists(select 1 from public.moa_workspaces w where w.id=target_workspace and w.owner_id=auth.uid())
    or exists(select 1 from public.moa_team_members m where m.workspace_id=target_workspace and lower(m.email)=lower(coalesce(auth.jwt()->>'email','')) and m.role='admin');
$$;

create or replace function public.moa_is_workspace_member(target_workspace uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists(select 1 from public.moa_workspaces w where w.id=target_workspace and w.owner_id=auth.uid())
    or exists(select 1 from public.moa_team_members m where m.workspace_id=target_workspace and lower(m.email)=lower(coalesce(auth.jwt()->>'email','')));
$$;

create or replace function public.moa_can_access_business(target_workspace uuid, target_business text)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select public.moa_is_workspace_admin(target_workspace)
    or exists(select 1 from public.moa_team_members m where m.workspace_id=target_workspace
      and lower(m.email)=lower(coalesce(auth.jwt()->>'email',''))
      and m.role in ('subadmin','employee') and target_business=any(m.business_ids));
$$;

alter table public.moa_workspaces enable row level security;
alter table public.moa_team_members enable row level security;
alter table public.moa_business_records enable row level security;
revoke all on public.moa_workspaces, public.moa_team_members, public.moa_business_records from anon;
grant select, insert, update, delete on public.moa_workspaces, public.moa_team_members, public.moa_business_records to authenticated;

drop policy if exists "moa workspace owner or member read" on public.moa_workspaces;
create policy "moa workspace owner or member read" on public.moa_workspaces for select to authenticated
using (public.moa_is_workspace_member(id));
drop policy if exists "moa workspace owner insert" on public.moa_workspaces;
create policy "moa workspace owner insert" on public.moa_workspaces for insert to authenticated with check (owner_id=auth.uid());
drop policy if exists "moa workspace admin update" on public.moa_workspaces;
create policy "moa workspace admin update" on public.moa_workspaces for update to authenticated using (public.moa_is_workspace_admin(id)) with check (public.moa_is_workspace_admin(id));
drop policy if exists "moa workspace owner delete" on public.moa_workspaces;
create policy "moa workspace owner delete" on public.moa_workspaces for delete to authenticated using (owner_id=auth.uid());

drop policy if exists "moa team member read own or admin" on public.moa_team_members;
create policy "moa team member read own or admin" on public.moa_team_members for select to authenticated
using (public.moa_is_workspace_admin(workspace_id) or lower(email)=lower(coalesce(auth.jwt()->>'email','')));
drop policy if exists "moa team member admin manage" on public.moa_team_members;
create policy "moa team member admin manage" on public.moa_team_members for all to authenticated
using (public.moa_is_workspace_admin(workspace_id)) with check (public.moa_is_workspace_admin(workspace_id));

drop policy if exists "moa business records category access" on public.moa_business_records;
create policy "moa business records category access" on public.moa_business_records for select to authenticated
using (public.moa_can_access_business(workspace_id,business_id));
drop policy if exists "moa business records category write" on public.moa_business_records;
create policy "moa business records category write" on public.moa_business_records for all to authenticated
using (public.moa_can_access_business(workspace_id,business_id)) with check (public.moa_can_access_business(workspace_id,business_id));
