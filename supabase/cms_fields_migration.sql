alter table public.tourism_content
  add column if not exists category_label text not null default 'Destination',
  add column if not exists place_label text not null default '';
