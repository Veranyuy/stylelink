-- ============================================================================
-- StyleLink — upgrade_to_provider RPC
-- ============================================================================
-- Called by the Flutter app when a client taps "Become a Provider".
-- 1. Validates inputs.
-- 2. Upserts a row into public.providers (id = auth.uid(), user_id = auth.uid()).
-- 3. Updates public.profiles.role = 'provider'.
--
-- Run this in the Supabase SQL editor. Idempotent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.upgrade_to_provider(
  p_business_name text,
  p_category      text,
  p_city          text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_business_name IS NULL OR trim(p_business_name) = '' THEN
    RAISE EXCEPTION 'Business name is required';
  END IF;

  IF p_category IS NULL OR trim(p_category) = '' THEN
    RAISE EXCEPTION 'Category is required';
  END IF;

  IF p_city IS NULL OR trim(p_city) = '' THEN
    RAISE EXCEPTION 'City is required';
  END IF;

  -- Upsert the provider row (id = user_id = auth.uid()).
  INSERT INTO public.providers (
    id, user_id, business_name, category, city
  ) VALUES (
    uid, uid, trim(p_business_name), trim(p_category), trim(p_city)
  )
  ON CONFLICT (id) DO UPDATE SET
    business_name = EXCLUDED.business_name,
    category      = EXCLUDED.category,
    city          = EXCLUDED.city;

  -- Update the profile role to provider.
  UPDATE public.profiles
  SET role = 'provider'
  WHERE id = uid;

  -- Also stamp auth metadata so the role persists across sessions.
  UPDATE auth.users
  SET raw_user_meta_data = raw_user_meta_data || '{"role": "provider"}'::jsonb
  WHERE id = uid;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upgrade_to_provider(text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.upgrade_to_provider(text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
