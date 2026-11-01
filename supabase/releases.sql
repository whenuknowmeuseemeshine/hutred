-- Hutred: корзина для автообновлений (публичная, только чтение).
-- Файлы туда кладёт облачная сборка GitHub с ключом service_role.
insert into storage.buckets (id, name, public, file_size_limit)
  values ('releases', 'releases', true, 52428800)
  on conflict (id) do update set public = true, file_size_limit = 52428800;
