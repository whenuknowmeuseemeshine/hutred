-- Hutred: логины, аватарки, роль админа, общие настройки, облако для файлов.
-- Выполни целиком в Supabase → SQL Editor → New query → Run.
-- Можно запускать повторно: всё написано так, чтобы не ломаться.

-- ===== Профили: логин, аватарка, роль =====
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text unique check (username ~ '^[A-Za-z0-9_.]{3,24}$'),
  avatar_url text,
  role       text not null default 'user' check (role in ('user', 'admin')),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Логины видят все вошедшие (нужно, чтобы проверять, что логин свободен).
drop policy if exists "profiles: read" on public.profiles;
create policy "profiles: read" on public.profiles
  for select to authenticated using (true);

drop policy if exists "profiles: insert own" on public.profiles;
create policy "profiles: insert own" on public.profiles
  for insert to authenticated with check (auth.uid() = id and role = 'user');

drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Роль сам себе поменять нельзя: менять разрешено только логин и аватарку.
revoke update on public.profiles from authenticated;
grant update (username, avatar_url, updated_at) on public.profiles to authenticated;

-- Профиль создаётся сам при регистрации (логин берётся из формы).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    insert into public.profiles (id, username)
    values (new.id, nullif(new.raw_user_meta_data ->> 'username', ''))
    on conflict (id) do nothing;
  exception when unique_violation or check_violation then
    -- Логин занят или неправильный — профиль без логина, его можно задать потом.
    insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  end;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Профили для тех, кто зарегистрировался раньше.
insert into public.profiles (id) select id from auth.users on conflict (id) do nothing;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ===== Общие настройки (их меняет только админ) =====
create table if not exists public.app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

drop policy if exists "config: read" on public.app_config;
create policy "config: read" on public.app_config
  for select to authenticated using (true);

drop policy if exists "config: admin write" on public.app_config;
create policy "config: admin write" on public.app_config
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ===== Хранилище: аватарки (видны всем) и свои треки (видны только владельцу) =====
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit)
  values ('tracks', 'tracks', false, 52428800) on conflict (id) do nothing;

drop policy if exists "avatars: read" on storage.objects;
create policy "avatars: read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars: write own" on storage.objects;
create policy "avatars: write own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars: update own" on storage.objects;
create policy "avatars: update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars: delete own" on storage.objects;
create policy "avatars: delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "tracks: own" on storage.objects;
create policy "tracks: own" on storage.objects
  for all to authenticated
  using (bucket_id = 'tracks' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'tracks' and (storage.foldername(name))[1] = auth.uid()::text);

-- ===== Админ =====
-- Впиши свою почту (ту, с которой входишь в Hutred) и выполни.
update public.profiles set role = 'admin'
  where id = (select id from auth.users where email = 'lxlpreame88@gmail.com');
