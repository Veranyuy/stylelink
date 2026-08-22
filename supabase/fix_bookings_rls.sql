-- ============================================================================
-- StyleLink — restore the `bookings` row-level-security policies
-- Run this in the Supabase SQL editor (idempotent; safe to re-run).
--
-- The deployed `bookings` table has the read policies (clients see their own,
-- providers see their schedule) but is missing the write policies, so a
-- client confirming "Book Now" fails with:
--   PostgresException 42501 "new row violates row-level security policy
--   for table bookings"
-- The same gap blocks the provider Accept / Cancel actions and the client's
-- Cancel Booking action on rows created later.
-- ============================================================================

-- Clients insert new booking requests.
drop policy if exists "clients can request bookings" on public.bookings;
create policy "clients can request bookings"
  on public.bookings for insert with check (auth.uid() = client_id);

-- Providers update status / notes on their schedule.
drop policy if exists "providers can update their schedule" on public.bookings;
create policy "providers can update their schedule"
  on public.bookings for update using (
    exists (
      select 1 from public.providers p
      where p.id = bookings.provider_id and p.user_id = auth.uid()
    )
  );

-- Providers may delete bookings on their schedule (e.g. removing junk or
-- test rows). Kept deliberately provider-only: the app lets clients
-- *cancel* their own bookings (status -> 'cancelled') but never delete them,
-- so no client-side DELETE policy is created here.
drop policy if exists "providers can delete their own bookings" on public.bookings;
create policy "providers can delete their own bookings"
  on public.bookings for delete using (
    exists (
      select 1 from public.providers p
      where p.id = bookings.provider_id and p.user_id = auth.uid()
    )
  );

-- Clients may cancel their own upcoming bookings (status -> 'cancelled').
drop policy if exists "clients can cancel their own bookings" on public.bookings;
create policy "clients can cancel their own bookings"
  on public.bookings for update
  using (auth.uid() = client_id)
  with check (auth.uid() = client_id and status = 'cancelled');

-- Sanity check after running: as a signed-in client, inserting a booking row
-- with your own client_id should now succeed (201) instead of 403.
