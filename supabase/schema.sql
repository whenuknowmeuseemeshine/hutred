-- Hutred: таблица медиатеки пользователей.
-- Выполни целиком в Supabase → SQL Editor → New query → Run.

create table if not exists public.library_items (
  user_id    uuid        not null references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('track', 'playlist')),
  item_id    text        not null,
  data       jsonb,
  deleted    boolean     not null default false,
  updated_at timestamptz not null,
  primary key (user_id, kind, item_id)
);

create index if not exists library_items_user_updated
  on public.library_items (user_id, updated_at);

-- Каждый видит и меняет только свою медиатеку.
alter table public.library_items enable row level security;

drop policy if exists "own items: read" on public.library_items;
create policy "own items: read" on public.library_items
  for select using (auth.uid() = user_id);

drop policy if exists "own items: insert" on public.library_items;
create policy "own items: insert" on public.library_items
  for insert with check (auth.uid() = user_id);

drop policy if exists "own items: update" on public.library_items;
create policy "own items: update" on public.library_items
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own items: delete" on public.library_items;
create policy "own items: delete" on public.library_items
  for delete using (auth.uid() = user_id);
