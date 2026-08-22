-- ============================================================================
-- StyleLink — provider cover photo storage
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
-- Canonical copy lives at the bottom of supabase/schema.sql.
--
-- The "List / Edit My Business" screen uploads the cover photo to this
-- bucket at `covers/<user_id>.jpg` and stores the public URL in
-- `providers.cover_url`. The bucket must exist (and be public) before the
-- upload works.
-- ============================================================================

-- Public bucket for provider cover images.
insert into storage.buckets (id, name, public)
values ('provider_assets', 'provider_assets', true)
on conflict (id) do nothing;

-- Anyone can read covers (public bucket).
drop policy if exists "provider covers are readable" on storage.objects;
create policy "provider covers are readable"
  on storage.objects for select
  using (bucket_id = 'provider_assets');

-- Signed-in users may upload/overwrite their own cover only.
drop policy if exists "users upload their own covers" on storage.objects;
create policy "users upload their own covers"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'provider_assets'
    and (storage.foldername(name))[1] = 'covers'
  );

drop policy if exists "users update their own covers" on storage.objects;
create policy "users update their own covers"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'provider_assets' and owner = auth.uid())
  with check (
    bucket_id = 'provider_assets'
    and (storage.foldername(name))[1] = 'covers'
  );

drop policy if exists "users delete their own covers" on storage.objects;
create policy "users delete their own covers"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'provider_assets' and owner = auth.uid());
