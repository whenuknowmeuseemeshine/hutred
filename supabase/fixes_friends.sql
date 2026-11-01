-- Hutred: исправления треков от админа и друзья.
-- Выполни целиком в Supabase → SQL Editor → New query → Run. Можно запускать повторно.

-- ===== Исправления треков (текст, тайминги, сведения, обложка) =====
-- Ключ: «youtube:<id>», «soundcloud:<id>», «url:<ссылка>» или «meta:исполнитель|название» для файлов.
create table if not exists public.track_fixes (
  key        text primary key,
  data       jsonb not null,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.track_fixes enable row level security;

drop policy if exists "fixes: read" on public.track_fixes;
create policy "fixes: read" on public.track_fixes
  for select to authenticated using (true);

drop policy if exists "fixes: admin write" on public.track_fixes;
create policy "fixes: admin write" on public.track_fixes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ===== Друзья =====
alter table public.profiles add column if not exists library_public boolean not null default true;
grant update (library_public) on public.profiles to authenticated;

create table if not exists public.friendships (
  id         bigint generated always as identity primary key,
  requester  uuid not null references auth.users (id) on delete cascade,
  addressee  uuid not null references auth.users (id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  check (requester <> addressee)
);

-- Одна заявка на пару людей, в какую бы сторону её ни отправили.
create unique index if not exists friendships_pair
  on public.friendships (least(requester, addressee), greatest(requester, addressee));

alter table public.friendships enable row level security;

drop policy if exists "friends: read own" on public.friendships;
create policy "friends: read own" on public.friendships
  for select to authenticated using (auth.uid() in (requester, addressee));

drop policy if exists "friends: request" on public.friendships;
create policy "friends: request" on public.friendships
  for insert to authenticated with check (requester = auth.uid() and status = 'pending');

drop policy if exists "friends: accept" on public.friendships;
create policy "friends: accept" on public.friendships
  for update to authenticated using (addressee = auth.uid()) with check (addressee = auth.uid());

drop policy if exists "friends: remove" on public.friendships;
create policy "friends: remove" on public.friendships
  for delete to authenticated using (auth.uid() in (requester, addressee));

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a))
  );
$$;

-- Друг видит треки из моей медиатеки, если я её не скрыл и трек не скрыт.
drop policy if exists "friends: read library" on public.library_items;
create policy "friends: read library" on public.library_items
  for select to authenticated using (
    kind = 'track'
    and deleted = false
    and coalesce((data ->> 'hiddenFromFriends')::boolean, false) = false
    and exists (select 1 from public.profiles p where p.id = user_id and p.library_public)
    and public.are_friends(auth.uid(), user_id)
  );
