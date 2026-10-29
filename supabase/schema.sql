-- Destination Gabon — schéma initial Supabase / PostgreSQL
-- À exécuter dans Supabase > SQL Editor. Ne jamais mettre la clé service_role dans le site.

create extension if not exists pgcrypto;

create table if not exists public.provinces (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  province_id uuid not null references public.provinces(id) on delete restrict,
  name text not null,
  slug text not null,
  created_at timestamptz not null default now(),
  unique(province_id, slug)
);

create table if not exists public.localities (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete restrict,
  name text not null,
  slug text not null,
  created_at timestamptz not null default now(),
  unique(department_id, slug)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  role text not null default 'provider'
    check (role in ('national_admin','provincial_guide','departmental_guide','provider')),
  province_id uuid references public.provinces(id),
  department_id uuid references public.departments(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (role = 'national_admin' and province_id is null and department_id is null)
    or (role = 'provincial_guide' and province_id is not null and department_id is null)
    or (role = 'departmental_guide' and province_id is not null and department_id is not null)
    or (role = 'provider')
  )
);

create table if not exists public.providers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  category text not null,
  description text not null default '',
  phone text,
  email text,
  website text,
  address text,
  province_id uuid references public.provinces(id),
  department_id uuid references public.departments(id),
  locality_id uuid references public.localities(id),
  status text not null default 'pending' check (status in ('pending','provincial_review','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tourism_content (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  content_type text not null check (content_type in ('site','culture','history','event','experience')),
  description text not null default '',
  image_url text,
  province_id uuid references public.provinces(id),
  department_id uuid references public.departments(id),
  locality_id uuid references public.localities(id),
  status text not null default 'draft' check (status in ('draft','pending','published','rejected')),
  author_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid references public.providers(id) on delete set null,
  visitor_name text not null,
  visitor_email text,
  visitor_phone text,
  message text not null,
  status text not null default 'new' check (status in ('new','in_progress','closed')),
  created_at timestamptz not null default now()
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers(id) on delete restrict,
  visitor_name text not null,
  visitor_email text,
  visitor_phone text,
  start_date date,
  party_size integer check (party_size is null or party_size > 0),
  message text,
  status text not null default 'requested' check (status in ('requested','confirmed','declined','cancelled')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    new.raw_user_meta_data->>'phone',
    'provider'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.current_province()
returns uuid language sql stable security definer set search_path = public
as $$
  select province_id from public.profiles where id = auth.uid()
$$;

create or replace function public.current_department()
returns uuid language sql stable security definer set search_path = public
as $$
  select department_id from public.profiles where id = auth.uid()
$$;

alter table public.profiles enable row level security;
alter table public.provinces enable row level security;
alter table public.departments enable row level security;
alter table public.localities enable row level security;
alter table public.providers enable row level security;
alter table public.tourism_content enable row level security;
alter table public.inquiries enable row level security;
alter table public.reservations enable row level security;

-- Référentiels territoriaux consultables publiquement.
create policy "territories are readable" on public.provinces for select using (true);
create policy "departments are readable" on public.departments for select using (true);
create policy "localities are readable" on public.localities for select using (true);

-- Les profils ne sont visibles que par leur propriétaire et l'administration.
create policy "profile owner or national admin reads" on public.profiles
for select using (id = auth.uid() or public.current_role() = 'national_admin');
create policy "profile owner updates own contact" on public.profiles
for update using (id = auth.uid()) with check (id = auth.uid() and role = (select p.role from public.profiles p where p.id = auth.uid()));

-- Fiches approuvées publiques ; chaque professionnel gère les siennes.
create policy "approved providers public, scoped users read" on public.providers
for select using (
  status = 'approved'
  or owner_id = auth.uid()
  or public.current_role() = 'national_admin'
  or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
  or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
);
create policy "provider creates own pending listing" on public.providers
for insert with check (owner_id = auth.uid() and public.current_role() = 'provider' and status = 'pending');
create policy "provider updates own pending listing" on public.providers
for update using (owner_id = auth.uid() and status in ('pending','rejected'))
with check (owner_id = auth.uid() and status in ('pending','rejected'));

-- Contenus publiés visibles publiquement ; guides travaillent dans leur territoire.
create policy "published content public or scoped team" on public.tourism_content
for select using (
  status = 'published'
  or author_id = auth.uid()
  or public.current_role() = 'national_admin'
  or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
  or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
);
create policy "team creates content in assigned territory" on public.tourism_content
for insert with check (
  author_id = auth.uid() and (
    public.current_role() = 'national_admin'
    or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
    or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
  )
);
create policy "team updates own or scoped content" on public.tourism_content
for update using (
  public.current_role() = 'national_admin'
  or author_id = auth.uid()
  or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
  or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
);

-- Les demandes visiteurs peuvent être envoyées sans compte.
create policy "visitors submit inquiries" on public.inquiries
for insert with check (true);
create policy "national admin and provider read inquiries" on public.inquiries
for select using (
  public.current_role() = 'national_admin'
  or exists (select 1 from public.providers p where p.id = provider_id and p.owner_id = auth.uid())
);
create policy "visitors submit reservation requests" on public.reservations
for insert with check (true);
create policy "national admin and provider read reservations" on public.reservations
for select using (
  public.current_role() = 'national_admin'
  or exists (select 1 from public.providers p where p.id = provider_id and p.owner_id = auth.uid())
);
create policy "national admin or provider updates reservations" on public.reservations
for update using (
  public.current_role() = 'national_admin'
  or exists (select 1 from public.providers p where p.id = provider_id and p.owner_id = auth.uid())
);

-- Accès complet réservé à l'administration nationale pour les validations.
create policy "national admin manages providers" on public.providers
for all using (public.current_role() = 'national_admin')
with check (public.current_role() = 'national_admin');

insert into public.provinces (name, slug) values
('Estuaire','estuaire'),('Haut-Ogooué','haut-ogooue'),('Moyen-Ogooué','moyen-ogooue'),
('Ngounié','ngounie'),('Nyanga','nyanga'),('Ogooué-Ivindo','ogooue-ivindo'),
('Ogooué-Lolo','ogooue-lolo'),('Ogooué-Maritime','ogooue-maritime'),('Woleu-Ntem','woleu-ntem')
on conflict (slug) do nothing;

-- IMPORTANT : crée le premier compte dans Authentication, puis attribue le rôle national_admin
-- manuellement depuis SQL Editor après avoir récupéré son UUID :
-- update public.profiles set role='national_admin' where id='UUID_DU_COMPTE';
