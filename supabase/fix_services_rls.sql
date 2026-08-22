-- ============================================================================
-- StyleLink — restore the `services` row-level-security policies
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed `services` table only has the public SELECT policy, so a
-- provider publishing (inserting) a service fails with:
--   PostgresException 42501 "new row violates row-level security policy
--   for table services"
-- The same missing policy also blocks UPDATE (edit) and DELETE (remove) of
-- existing listings from the provider's Service Manager screen.
-- ============================================================================

-- Providers can create/edit/delete services belonging to their own provider
-- row (checked through `providers.user_id = auth.uid()`).
drop policy if exists "providers can manage their own services" on public.services;
create policy "providers can manage their own services"
  on public.services for all using (
    exists (
      select 1 from public.providers p
      where p.id = services.provider_id and p.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.providers p
      where p.id = services.provider_id and p.user_id = auth.uid()
    )
  );

-- Sanity check after running: as a provider, inserting a service row with
-- your own provider_id should now succeed (201) instead of 403.
