-- Hutred: плейлисты по ссылке (снимок плейлиста, который можно открыть другу)
create table if not exists public.shared_playlists (
  id text primary key,
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  description text default '',
  cover text,
  tracks jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.shared_playlists enable row level security;
create policy "shared playlists: read" on public.shared_playlists
  for select to authenticated using (true);
create policy "shared playlists: owner writes" on public.shared_playlists
  for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
