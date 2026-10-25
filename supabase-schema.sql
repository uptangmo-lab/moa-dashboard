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


-- Create a first workspace through a tightly scoped server function so a stale
-- client-side RLS INSERT policy cannot block an approved first-time owner.
create or replace function public.moa_create_workspace(
  p_workspace_name text,
  p_admin_email text,
  p_currency text,
  p_workspace_goal_krw numeric
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  actor_id uuid := auth.uid();
  actor_email text := lower(trim(coalesce(auth.jwt()->>'email','')));
  new_workspace_id uuid;
begin
  if actor_id is null or actor_email = '' then
    raise exception '로그인이 필요합니다.';
  end if;
  if not public.moa_is_invited(actor_email) then
    raise exception '승인된 이메일이 아닙니다.';
  end if;
  if exists (select 1 from public.moa_team_members m where lower(m.email)=actor_email) then
    raise exception '이 이메일은 이미 다른 워크스페이스에 초대되어 있습니다.';
  end if;
  if exists (select 1 from public.moa_workspaces w where w.owner_id=actor_id) then
    raise exception '이 계정의 워크스페이스가 이미 존재합니다.';
  end if;
  insert into public.moa_workspaces(owner_id, workspace_name, admin_email, currency, workspace_goal_krw)
  values (actor_id, left(trim(coalesce(p_workspace_name,'')),40), trim(coalesce(p_admin_email,'')), p_currency, p_workspace_goal_krw)
  returning id into new_workspace_id;
  return new_workspace_id;
end;
$$;
revoke all on function public.moa_create_workspace(text,text,text,numeric) from public, anon;
grant execute on function public.moa_create_workspace(text,text,text,numeric) to authenticated;


-- Transfer the first email-based owner to the new username-backed Auth account.
create or replace function public.moa_transfer_workspace_owner(
  p_workspace_id uuid,
  p_new_owner_id uuid,
  p_new_login_email text
)
returns void
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if not exists(select 1 from public.moa_workspaces where id=p_workspace_id and owner_id=auth.uid()) then
    raise exception '현재 워크스페이스 관리자만 전환할 수 있습니다.';
  end if;
  if lower(trim(p_new_login_email)) !~ '^[a-z0-9._-]{3,32}@moa-login[.]invalid$' then
    raise exception '아이디 형식이 올바르지 않습니다.';
  end if;
  if not exists(select 1 from auth.users where id=p_new_owner_id and lower(email)=lower(trim(p_new_login_email))) then
    raise exception '새 아이디 계정을 확인할 수 없습니다.';
  end if;
  update public.moa_workspaces set owner_id=p_new_owner_id,updated_at=now() where id=p_workspace_id and owner_id=auth.uid();
end;
$$;
revoke all on function public.moa_transfer_workspace_owner(uuid,uuid,text) from public, anon;
grant execute on function public.moa_transfer_workspace_owner(uuid,uuid,text) to authenticated;

-- Support USDT as a display currency for workspace summaries.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
    where conrelid='public.moa_workspaces'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%currency%'
  loop execute format('alter table public.moa_workspaces drop constraint %I',c.conname); end loop;
end $$;
alter table public.moa_workspaces add constraint moa_workspaces_currency_check
  check (currency in ('KRW','THB','USD','USDT'));
