-- 모아 온라인 대시보드: 사용자별 워크스페이스 데이터
create table if not exists public.moa_workspace_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  workspace_name text not null default '내 워크스페이스',
  payload jsonb not null default '{"businesses":[],"transactions":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.moa_workspace_state enable row level security;

revoke all on table public.moa_workspace_state from anon;
grant select, insert, update, delete on table public.moa_workspace_state to authenticated;

drop policy if exists "Users can access only their own Moa workspace" on public.moa_workspace_state;
create policy "Users can access only their own Moa workspace"
on public.moa_workspace_state
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
