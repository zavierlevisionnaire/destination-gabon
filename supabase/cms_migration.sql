-- Destination Gabon : complément CMS + durcissement des profils
alter table public.tourism_content
  add column if not exists excerpt text not null default '',
  add column if not exists updated_at timestamptz not null default now();

-- Un utilisateur ne peut pas s'attribuer un rôle ou changer son territoire.
drop policy if exists "profile owner updates own contact" on public.profiles;
create policy "profile owner updates own contact" on public.profiles
for update using (id = auth.uid())
with check (
  id = auth.uid()
  and role = (select p.role from public.profiles p where p.id = auth.uid())
  and province_id is not distinct from (select p.province_id from public.profiles p where p.id = auth.uid())
  and department_id is not distinct from (select p.department_id from public.profiles p where p.id = auth.uid())
);

-- Seul l'administrateur national peut modifier les profils et affecter les rôles.
drop policy if exists "national admin manages profiles" on public.profiles;
create policy "national admin manages profiles" on public.profiles
for all using (public.current_role() = 'national_admin')
with check (public.current_role() = 'national_admin');

-- Politique explicite de modification du CMS dans le périmètre territorial.
drop policy if exists "team updates own or scoped content" on public.tourism_content;
create policy "team updates own or scoped content" on public.tourism_content
for update using (
  public.current_role() = 'national_admin'
  or author_id = auth.uid()
  or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
  or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
)
with check (
  public.current_role() = 'national_admin'
  or author_id = auth.uid()
  or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
  or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
);

-- Index utiles au CMS.
create index if not exists tourism_content_status_idx on public.tourism_content(status);
create index if not exists tourism_content_province_idx on public.tourism_content(province_id);
create index if not exists tourism_content_updated_idx on public.tourism_content(updated_at desc);
