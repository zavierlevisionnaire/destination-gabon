-- Autoriser la suppression des contenus uniquement dans le périmètre de l'utilisateur.
drop policy if exists "team deletes scoped content" on public.tourism_content;
create policy "team deletes scoped content" on public.tourism_content
for delete using (
  public.current_role() = 'national_admin'
  or author_id = auth.uid()
  or (public.current_role() = 'provincial_guide' and province_id = public.current_province())
  or (public.current_role() = 'departmental_guide' and department_id = public.current_department())
);
