-- Hutred: защита базы.
-- Выполни целиком в Supabase → SQL Editor → New query → Run.
-- Можно запускать повторно: всё написано так, чтобы не ломаться.

-- ===== 1. Секретные ключи — отдельно, их видит только админ и сервер =====
-- Раньше ключ ИИ и секрет Spotify лежали в app_config, который читает
-- любой вошедший пользователь. Теперь они в app_secrets, а функции на
-- сервере ходят в ИИ/Spotify сами — ключи в приложение не попадают.
create table if not exists public.app_secrets (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_secrets enable row level security;

drop policy if exists "secrets: admin" on public.app_secrets;
create policy "secrets: admin" on public.app_secrets
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Переносим уже сохранённые ключи и убираем их из общих настроек.
insert into public.app_secrets (key, value)
  select key, value from public.app_config
  where key = 'ai' and coalesce(value ->> 'key', '') <> ''
  on conflict (key) do update set value = excluded.value, updated_at = now();
insert into public.app_secrets (key, value)
  select key, value from public.app_config
  where key = 'spotify' and coalesce(value ->> 'secret', '') <> ''
  on conflict (key) do update set value = excluded.value, updated_at = now();

update public.app_config set value = jsonb_build_object('enabled', true), updated_at = now()
  where key in ('ai', 'spotify') and (value ? 'key' or value ? 'secret');

-- ===== 2. Лимиты запросов (для функций на сервере) =====
create table if not exists public.rate_hits (
  bucket text not null,
  at     timestamptz not null default now()
);
create index if not exists rate_hits_bucket_at on public.rate_hits (bucket, at);
alter table public.rate_hits enable row level security;
-- Политик нет: таблицу видит только сервер (service_role).

-- true — можно, false — лимит исчерпан. Вызывает только сервер.
create or replace function public.rate_hit(p_bucket text, p_max int, p_seconds int)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.rate_hits where at < now() - interval '1 day';
  select count(*) into n from public.rate_hits
    where bucket = p_bucket and at > now() - make_interval(secs => p_seconds);
  if n >= p_max then return false; end if;
  insert into public.rate_hits (bucket) values (p_bucket);
  return true;
end $$;

revoke all on function public.rate_hit(text, int, int) from public, anon, authenticated;
grant execute on function public.rate_hit(text, int, int) to service_role;

-- Почта по логину — только для сервера (вход по логину). Пользователям
-- чужие почты не видны.
create or replace function public.email_for_username(p_username text)
returns text language sql stable security definer set search_path = public, auth as $$
  select u.email from public.profiles p join auth.users u on u.id = p.id
  where lower(p.username) = lower(p_username) limit 1;
$$;

revoke all on function public.email_for_username(text) from public, anon, authenticated;
grant execute on function public.email_for_username(text) to service_role;

-- ===== 3. Размеры записей: чтобы никто не забил базу мусором =====
alter table public.library_items drop constraint if exists library_items_data_size;
alter table public.library_items add constraint library_items_data_size
  check (data is null or octet_length(data::text) <= 2000000) not valid;
alter table public.library_items drop constraint if exists library_items_id_size;
alter table public.library_items add constraint library_items_id_size
  check (octet_length(item_id) <= 600) not valid;

alter table public.shared_playlists drop constraint if exists shared_playlists_size;
alter table public.shared_playlists add constraint shared_playlists_size
  check (octet_length(tracks::text) <= 3000000
         and char_length(name) <= 200
         and char_length(coalesce(description, '')) <= 2000
         and octet_length(id) <= 100) not valid;

-- Аватарка — только https-ссылка разумной длины.
alter table public.profiles drop constraint if exists profiles_avatar_url;
alter table public.profiles add constraint profiles_avatar_url
  check (avatar_url is null or (avatar_url ~ '^https://' and char_length(avatar_url) <= 600)) not valid;

-- ===== 4. Файлы: только картинки и только звук, с лимитами размера =====
update storage.buckets
  set file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  where id = 'avatars';
update storage.buckets
  set file_size_limit = 52428800,
      allowed_mime_types = array['audio/*']
  where id = 'tracks';

-- ===== 5. Закрытые каналы (синхронизация устройств, джем, кто онлайн) =====
-- В канал устройств пускает только владельца, в джем — хозяина и его друзей,
-- в «кто онлайн» — только вошедших.
create or replace function public.can_use_channel(topic text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); host uuid;
begin
  if me is null then return false; end if;
  if topic = 'hutred-online' then return true; end if;
  if topic = 'devices-' || me::text then return true; end if;
  if topic like 'jam-%' then
    begin
      host := substr(topic, 5)::uuid;
    exception when others then
      return false;
    end;
    return host = me or public.are_friends(me, host);
  end if;
  return false;
end $$;

drop policy if exists "hutred: listen" on realtime.messages;
create policy "hutred: listen" on realtime.messages
  for select to authenticated using (public.can_use_channel(realtime.topic()));

drop policy if exists "hutred: send" on realtime.messages;
create policy "hutred: send" on realtime.messages
  for insert to authenticated with check (public.can_use_channel(realtime.topic()));
